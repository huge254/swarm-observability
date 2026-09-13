#!/bin/bash
# 项目4 全栈验收：采集目标 / 告警规则 / 业务链路 / 中间件
set -u

echo "################## 1. 服务总览 ##################"
docker stack services order-observability --format '  {{.Name}}  {{.Replicas}}  {{.Ports}}' 2>&1

echo
echo "################## 2. 任务分布 ##################"
docker stack ps order-observability --format '  {{.Name}}\t{{.Node}}\t{{.CurrentState}}' 2>&1 | sed 's/\t/  |  /g' | head -30

echo
echo "################## 3. 组件就绪性 ##################"
for c in "prometheus http://127.0.0.1:9090/-/ready" "grafana http://127.0.0.1:3000/api/health" "alertmanager http://127.0.0.1:9093/-/ready" "order-api http://127.0.0.1:8000/health" "webhook http://127.0.0.1:8080/health" "loki http://127.0.0.1:3100/ready"; do
  n=$(echo $c | cut -d' ' -f1); u=$(echo $c | cut -d' ' -f2)
  code=$(curl -s -m 6 -o /tmp/r.txt -w '%{http_code}' "$u" 2>/dev/null)
  printf "  %-14s %s  %s\n" "$n" "$code" "$(head -c 90 /tmp/r.txt 2>/dev/null | tr -d '\n')"
done

echo
echo "################## 4. Prometheus 采集目标 ##################"
curl -s -m 10 'http://127.0.0.1:9090/api/v1/targets?state=active' 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception as e:
    print('  解析失败: %s' % e); raise SystemExit
ts = d.get('data', {}).get('activeTargets', [])
up = 0
print('  目标总数: %d' % len(ts))
for t in sorted(ts, key=lambda x: (x['labels'].get('job',''), x['labels'].get('instance',''))):
    h = t.get('health')
    if h == 'up': up += 1
    print('    %-6s %-10s %-22s %s' % (h, t['labels'].get('job',''), t['labels'].get('instance',''), (t.get('lastError') or '')[:50]))
print('  ===> up: %d / %d' % (up, len(ts)))
"

echo
echo "################## 5. 告警规则加载 ##################"
curl -s -m 10 http://127.0.0.1:9090/api/v1/rules 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
tot = 0
for g in d.get('data', {}).get('groups', []):
    names = [r['name'] for r in g['rules']]
    tot += len(names)
    print('  组 %-18s %d 条: %s' % (g['name'], len(names), ', '.join(names)))
print('  ===> 规则总数: %d' % tot)
"

echo
echo "################## 6. 当前活跃告警 ##################"
curl -s -m 10 http://127.0.0.1:9090/api/v1/alerts 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
als = d.get('data', {}).get('alerts', [])
print('  活跃告警: %d 条' % len(als))
for a in als[:10]:
    print('    [%s] %s %s' % (a['state'], a['labels'].get('alertname'), a['labels'].get('instance','')))
"

echo
echo "################## 7. 业务链路端到端 ##################"
echo "  [7.1] 下单（写 MySQL 事务 + 扣库存）"
curl -s -m 10 -X POST http://127.0.0.1:8000/api/orders -H 'Content-Type: application/json' -d '{"sku":"SKU-1001","qty":2}' | head -c 300
echo
echo "  [7.2] 查询订单（走 Redis 缓存 + MySQL）"
curl -s -m 10 "http://127.0.0.1:8000/api/orders?limit=3" | head -c 400
echo
echo "  [7.3] 库存视图"
curl -s -m 10 http://127.0.0.1:8000/api/stats | head -c 400
echo
echo "  [7.4] 缓存命中（二次读取同一订单）"
curl -s -m 10 http://127.0.0.1:8000/api/orders/1 | head -c 200
echo
echo "  [7.5] 业务指标暴露"
curl -s -m 10 http://127.0.0.1:8000/metrics | grep -E '^(http_requests_total|orders_created_total|order_cache)' | head -8 | sed 's/^/    /'

echo
echo "################## 8. 中间件导出器 ##################"
echo "  [8.1] mysqld-exporter"
curl -s -m 8 http://127.0.0.1:9104/metrics 2>/dev/null | grep -E '^mysql_up|^mysql_global_status_threads_connected|^mysql_global_status_uptime' | head -5 | sed 's/^/    /'
echo "  [8.2] redis-exporter"
curl -s -m 8 http://127.0.0.1:9121/metrics 2>/dev/null | grep -E '^redis_up|^redis_connected_clients|^redis_memory_used_bytes' | head -5 | sed 's/^/    /'

echo
echo "################## 9. 容器层指标（自建导出器）##################"
curl -s -m 8 http://127.0.0.1:8081/metrics 2>/dev/null | grep -c '^container_' | sed 's/^/  本节点容器指标条数: /'
curl -s -m 8 http://127.0.0.1:8081/metrics 2>/dev/null | grep '^container_cpu_usage_percent' | head -3 | sed 's/^/    /'

echo
echo "################## 10. 节点层指标 ##################"
curl -s -m 8 http://127.0.0.1:9100/metrics 2>/dev/null | grep -E '^node_load1|^node_memory_MemAvailable_bytes|^node_filesystem_avail_bytes\{.*mountpoint="/"' | head -4 | sed 's/^/  /'
echo "VERIFY-DONE"
