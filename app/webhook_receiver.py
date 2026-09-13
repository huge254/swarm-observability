# -*- coding: utf-8 -*-
"""Alertmanager Webhook 接收端（v4）

与 v2 的差异：**读路径也做了容错**。

背景（本次演练真实暴露的平台级问题）：
  v1 在 Redis 不可用时 /alerts 直接返回 503，告警记录整体不可见；
  v2 把写路径改成了「Redis + 内存双写」，但 /alerts 仍然先同步查 Redis——
     当 Redis 所在服务被缩容到 0 时，overlay DNS 解析会阻塞，
     导致 /alerts 请求超时（实测 curl -m 6 被打满），查询接口等同不可用。
  v4 的做法：
      1) 内存缓冲始终先就绪，保证查询接口在任何情况下都能返回历史告警；
      2) 查询 Redis 使用 1 秒超时，并加 30 秒熔断（连续失败后短期不再尝试），
         避免每个请求都去撞一次慢超时。

结论性经验：**监控/告警链路自身的读路径，不应与被监控组件强耦合。**
"""
import json
import os
import threading
import time

import redis
from flask import Flask, request, jsonify

app = Flask(__name__)

REDIS_HOST = os.getenv('REDIS_HOST', 'redis')
REDIS_PORT = int(os.getenv('REDIS_PORT', '6379'))
REDIS_KEY = 'alerts:received'
MEM_LIMIT = int(os.getenv('MEM_LIMIT', '1000'))
BREAKER_SECONDS = int(os.getenv('BREAKER_SECONDS', '30'))

_LOCK = threading.RLock()
_MEM = []                 # 内存缓冲（最新在前）
_STATS = {'received': 0, 'redis_ok': 0, 'redis_fail': 0, 'redis_skipped': 0}
_BREAKER_UNTIL = 0.0      # 熔断截止时间戳


def _client():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT,
                       socket_connect_timeout=1, socket_timeout=1,
                       decode_responses=True)


def _key(rec):
    return '%s|%s|%s|%s' % (rec.get('alertname'), rec.get('instance'),
                            rec.get('status'), rec.get('startsAt'))


def _mem_snapshot():
    with _LOCK:
        return list(_MEM), dict(_STATS)


@app.route('/webhook', methods=['POST'])
def webhook():
    data = request.get_json(force=True, silent=True) or {}
    now = time.time()
    alerts = data.get('alerts', [])
    for a in alerts:
        rec = {
            'receive_ts': now,
            'alertname': a.get('labels', {}).get('alertname'),
            'severity': a.get('labels', {}).get('severity'),
            'instance': a.get('labels', {}).get('instance'),
            'status': a.get('status'),
            'startsAt': a.get('startsAt'),
            'summary': a.get('annotations', {}).get('summary'),
        }
        print(json.dumps(rec, ensure_ascii=False), flush=True)

        with _LOCK:
            _STATS['received'] += 1
            _MEM.insert(0, rec)
            del _MEM[MEM_LIMIT:]

        try:
            c = _client()
            c.lpush(REDIS_KEY, json.dumps(rec, ensure_ascii=False))
            c.ltrim(REDIS_KEY, 0, 999)
            c.close()
            with _LOCK:
                _STATS['redis_ok'] += 1
        except Exception as e:
            with _LOCK:
                _STATS['redis_fail'] += 1
            print('redis 写入失败（已落内存缓冲）: %s' % e, flush=True)

    return jsonify(received=len(alerts)), 200


@app.route('/alerts', methods=['GET'])
def list_alerts():
    global _BREAKER_UNTIL
    items = []
    seen = set()
    redis_err = None
    used_redis = False
    skipped = False

    if request.args.get('source') != 'memory':
        if time.time() < _BREAKER_UNTIL:
            skipped = True
            redis_err = 'circuit breaker open (redis recently failed)'
        else:
            try:
                c = _client()
                for i in c.lrange(REDIS_KEY, 0, -1):
                    rec = json.loads(i)
                    k = _key(rec)
                    if k not in seen:
                        seen.add(k)
                        items.append(rec)
                c.close()
                used_redis = True
                _BREAKER_UNTIL = 0.0
            except Exception as e:
                redis_err = str(e)
                _BREAKER_UNTIL = time.time() + BREAKER_SECONDS
                with _LOCK:
                    _STATS['redis_skipped'] += 1

    mem, stats = _mem_snapshot()
    for rec in mem:
        k = _key(rec)
        if k not in seen:
            seen.add(k)
            items.append(rec)

    items.sort(key=lambda x: x.get('receive_ts', 0), reverse=True)
    return jsonify(count=len(items), memory_buffered=len(mem),
                   redis_available=used_redis, redis_error=redis_err,
                   breaker_open=skipped, stats=stats, items=items), 200


@app.route('/stats')
def stats():
    mem, s = _mem_snapshot()
    s = dict(s)
    s['memory_buffered'] = len(mem)
    s['breaker_open'] = time.time() < _BREAKER_UNTIL
    return jsonify(s), 200


@app.route('/health')
def health():
    return 'OK', 200


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
