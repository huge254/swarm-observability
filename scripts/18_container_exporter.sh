#!/bin/bash
# 自研容器指标导出器（替代 cAdvisor）：通过 Docker API 采集容器层指标
# 原理与 cAdvisor 一致：读 /containers/{id}/stats 的 cpu_stats/precpu_stats 差分算 CPU 使用率
set -u
B=/opt/order-stack/container-exporter
mkdir -p $B

cat > $B/exporter.py <<'PYEOF'
# -*- coding: utf-8 -*-
"""容器指标导出器 —— 通过 Docker Engine API 采集容器级指标并以 Prometheus 格式暴露

镜像仓库不可达拿不到 cAdvisor 时的自建替代方案。指标命名与 cAdvisor 保持兼容，
因此既有的告警规则无需改动即可生效。
"""
import json
import socket
import http.client
import time
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SOCK = '/var/run/docker.sock'
PORT = int(os.getenv('EXPORTER_PORT', '8081'))


class UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, path, timeout=15):
        super().__init__('localhost', timeout=timeout)
        self.sock_path = path

    def connect(self):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(self.timeout)
        s.connect(self.sock_path)
        self.sock = s


def docker_get(path):
    c = UnixHTTPConnection(SOCK)
    try:
        c.request('GET', path)
        r = c.getresponse()
        body = r.read()
        return json.loads(body) if body else None
    finally:
        c.close()


def num(v):
    try:
        return float(v)
    except Exception:
        return 0.0


def collect():
    out = []
    containers = docker_get('/containers/json') or []
    for c in containers:
        cid = c['Id']
        name = (c.get('Names') or ['/unknown'])[0].lstrip('/')
        labels = c.get('Labels') or {}
        service = labels.get('com.docker.swarm.service.name', name)
        task = labels.get('com.docker.swarm.task.name', '')
        node = labels.get('com.docker.swarm.node.id', '')
        state = c.get('State', 'unknown')
        L = 'name="%s",service="%s",task="%s",node_id="%s"' % (name, service, task, node)

        out.append('container_status{%s} %d' % (L, 1 if state == 'running' else 0))

        try:
            st = docker_get('/containers/%s/stats?stream=false&one-shot=true' % cid)
        except Exception:
            st = None
        if not st:
            continue

        cst = st.get('cpu_stats', {}) or {}
        pst = st.get('precpu_stats', {}) or {}
        cpu_delta = num(cst.get('cpu_usage', {}).get('total_usage')) - \
                    num(pst.get('cpu_usage', {}).get('total_usage'))
        sys_delta = num(cst.get('system_cpu_usage')) - num(pst.get('system_cpu_usage'))
        online = num(cst.get('online_cpus')) or 1.0
        cpu_seconds = num(cst.get('cpu_usage', {}).get('total_usage')) / 1e9
        out.append('container_cpu_usage_seconds_total{%s} %.6f' % (L, cpu_seconds))
        if cpu_delta > 0 and sys_delta > 0:
            pct = (cpu_delta / sys_delta) * online * 100.0
        else:
            pct = 0.0
        out.append('container_cpu_usage_percent{%s} %.4f' % (L, pct))

        mem = st.get('memory_stats', {}) or {}
        out.append('container_memory_usage_bytes{%s} %d' % (L, int(num(mem.get('usage')))))
        out.append('container_memory_limit_bytes{%s} %d' % (L, int(num(mem.get('limit')))))
        cache = num((mem.get('stats') or {}).get('inactive_file'))
        out.append('container_memory_working_set_bytes{%s} %d'
                   % (L, int(max(num(mem.get('usage')) - cache, 0))))

        nets = st.get('networks', {}) or {}
        rx = sum(num(v.get('rx_bytes')) for v in nets.values())
        tx = sum(num(v.get('tx_bytes')) for v in nets.values())
        out.append('container_network_receive_bytes_total{%s} %d' % (L, int(rx)))
        out.append('container_network_transmit_bytes_total{%s} %d' % (L, int(tx)))

        blk = st.get('blkio_stats', {}).get('io_service_bytes_recursive') or []
        rd = sum(num(x.get('value')) for x in blk if x.get('op') == 'Read')
        wr = sum(num(x.get('value')) for x in blk if x.get('op') == 'Write')
        out.append('container_fs_reads_bytes_total{%s} %d' % (L, int(rd)))
        out.append('container_fs_writes_bytes_total{%s} %d' % (L, int(wr)))

    out.append('container_exporter_up 1')
    return '\n'.join(out) + '\n'


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/metrics'):
            try:
                body = collect().encode()
                self.send_response(200)
            except Exception as e:
                body = ('container_exporter_up 0\n# error: %s\n' % e).encode()
                self.send_response(500)
            self.send_header('Content-Type', 'text/plain; version=0.0.4')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path.startswith('/health'):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'OK\n')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args):
        pass


if __name__ == '__main__':
    print('容器指标导出器启动，监听 0.0.0.0:%d' % PORT, flush=True)
    ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()
PYEOF

echo "已写入 exporter.py（$(wc -l < $B/exporter.py) 行）"

echo
echo "=================== 构建导出器镜像 ==================="
REG=192.168.123.20:5000
rm -rf /opt/img/rfs-cex
cp -al /opt/img/rfs-app /opt/img/rfs-cex
mkdir -p /opt/img/rfs-cex/app
cp $B/exporter.py /opt/img/rfs-cex/app/
tar -C /opt/img/rfs-cex -c . 2>/dev/null | docker import - $REG/container-exporter:v1 >/dev/null 2>&1
docker run --rm $REG/container-exporter:v1 /usr/bin/python3 -c "import sys; sys.path.insert(0,'/app'); import exporter; print('  [OK] 容器指标导出器可导入')"

echo
echo "=================== 导出器指标自检 ==================="
docker run -d --name cex-test -p 18081:8081 -v /var/run/docker.sock:/var/run/docker.sock:ro \
  $REG/container-exporter:v1 /usr/bin/python3 /app/exporter.py >/dev/null 2>&1
sleep 4
curl -s http://127.0.0.1:18081/metrics 2>/dev/null | head -8
echo "..."
curl -s http://127.0.0.1:18081/metrics 2>/dev/null | grep -c '^container_' | sed 's/^/  本次采集到的容器指标条数: /'
docker rm -f cex-test >/dev/null 2>&1
echo "CONTAINER-EXPORTER-DONE"
