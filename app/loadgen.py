#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""订单服务负载发生器（纯标准库，无外部依赖）

用法：
  python3 loadgen.py --url http://127.0.0.1:8000 --concurrency 20 --duration 120
  python3 loadgen.py --url ... --mode error   # 全量打 /debug/error 制造 5xx
  python3 loadgen.py --url ... --mode slow --slow-ms 1200
"""
import argparse
import json
import random
import threading
import time
import urllib.request
import urllib.error

STAT = {'ok': 0, 'err': 0, 'other': 0}
LOCK = threading.Lock()
STOP = threading.Event()


def req(url, method='GET', body=None, timeout=8):
    data = None
    headers = {}
    if body is not None:
        data = json.dumps(body).encode()
        headers['Content-Type'] = 'application/json'
    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            resp.read()
            code = resp.status
    except urllib.error.HTTPError as e:
        code = e.code
    except Exception:
        code = 0
    with LOCK:
        if 200 <= code < 300:
            STAT['ok'] += 1
        elif code >= 500 or code == 0:
            STAT['err'] += 1
        else:
            STAT['other'] += 1


def worker(base, mode, slow_ms, skus):
    while not STOP.is_set():
        try:
            if mode == 'error':
                req(base + '/debug/error')
            elif mode == 'slow':
                req(base + '/debug/slow?ms=%d' % slow_ms)
            else:
                p = random.random()
                if p < 0.30:
                    req(base + '/api/orders', 'POST',
                        {'sku': random.choice(skus), 'qty': random.randint(1, 2)})
                elif p < 0.60:
                    req(base + '/api/orders/%d' % random.randint(1, 5))
                elif p < 0.85:
                    req(base + '/api/orders?limit=5')
                else:
                    req(base + '/api/stats')
        except Exception:
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--url', default='http://127.0.0.1:8000')
    ap.add_argument('--concurrency', type=int, default=20)
    ap.add_argument('--duration', type=int, default=60)
    ap.add_argument('--mode', default='normal', choices=['normal', 'error', 'slow'])
    ap.add_argument('--slow-ms', type=int, default=1200)
    args = ap.parse_args()

    skus = ['SKU-1001', 'SKU-1002', 'SKU-1003', 'SKU-1004']
    print('[loadgen] url=%s concurrency=%d duration=%ds mode=%s'
          % (args.url, args.concurrency, args.duration, args.mode), flush=True)

    threads = [threading.Thread(target=worker, args=(args.url, args.mode, args.slow_ms, skus), daemon=True)
               for _ in range(args.concurrency)]
    t0 = time.time()
    for t in threads:
        t.start()

    last = 0
    while time.time() - t0 < args.duration:
        time.sleep(5)
        with LOCK:
            s = dict(STAT)
        tot = s['ok'] + s['err'] + s['other']
        now = time.time() - t0
        print('[loadgen] t=%5.1fs total=%6d ok=%6d err=%6d other=%5d qps=%.1f'
              % (now, tot, s['ok'], s['err'], s['other'], (tot - last) / 5.0), flush=True)
        last = tot

    STOP.set()
    time.sleep(1)
    with LOCK:
        s = dict(STAT)
    tot = s['ok'] + s['err'] + s['other']
    print('[loadgen] 结束: total=%d ok=%d err=%d other=%d 平均QPS=%.1f'
          % (tot, s['ok'], s['err'], s['other'], tot / max(time.time() - t0, 1)), flush=True)


if __name__ == '__main__':
    main()
