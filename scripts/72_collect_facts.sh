#!/bin/bash
# 收集文档所需的实测环境数据
set -u
PROM=http://127.0.0.1:9090

echo "################## A. 集群与版本 ##################"
echo "  Docker:  $(docker version --format '{{.Server.Version}}')"
echo "  Swarm:   $(docker info 2>/dev/null | grep -o 'Swarm: .*')"
docker node ls --format '    {{.Hostname}}  {{.Status}}  {{.ManagerStatus}}  {{.EngineVersion}}' 2>&1

echo
echo "################## B. 栈服务清单 ##################"
docker stack services order-observability --format '    {{.Name}}  {{.Replicas}}  {{.Image}}' 2>&1

echo
echo "################## C. 镜像仓库 ##################"
for r in $(curl -s -m 8 http://192.168.123.20:5000/v2/_catalog | tr -d '{}"' | sed 's/repositories://' | tr ',' ' '); do
  t=$(curl -s -m 5 "http://192.168.123.20:5000/v2/$r/tags/list" | sed 's/.*\[\(.*\)\].*/\1/' | tr -d '"')
  printf "    %-22s %s\n" "$r" "$t"
done

echo
echo "################## D. 组件版本 ##################"
curl -s -m 6 http://127.0.0.1:3000/api/health 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print('  Grafana:      %s' % d.get('version'))" 2>/dev/null
curl -s -m 6 http://127.0.0.1:9093/api/v2/status 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print('  Alertmanager: %s' % d.get('versionInfo',{}).get('version'))" 2>/dev/null
curl -s -m 6 http://127.0.0.1:9090/api/v1/status/buildinfo 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print('  Prometheus:   %s' % d['data'].get('version'))" 2>/dev/null
echo "  Loki:         $(curl -s -m 6 http://127.0.0.1:3100/loki/api/v1/status/buildinfo 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin).get("version"))' 2>/dev/null)"

echo
echo "################## E. 告警规则清单 ##################"
curl -s -m 10 $PROM/api/v1/rules 2>/dev/null | python3 -c "
import sys, json
d=json.load(sys.stdin)
n=0
for g in d.get('data',{}).get('groups',[]):
    print('  [%s]' % g['name'])
    for r in g['rules']:
        n+=1
        print('    %2d. %-28s severity=%s' % (n, r['name'], r.get('labels',{}).get('severity','-')))
print('  合计: %d 条' % n)
"

echo
echo "################## F. 资源占用 ##################"
echo "  各节点内存:"
for ip in 20 21 22 23 24; do
  m=$(curl -s -m 6 "$PROM/api/v1/query?query=(1-node_memory_MemAvailable_bytes/1024/1024/node_memory_MemTotal_bytes*1024)*100" 2>/dev/null | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)['data']['result']
  for r in d:
    if '192.168.$ip' in str(r):
      pass
except: pass
" 2>/dev/null)
done
curl -s -m 8 "$PROM/api/v1/query?query=node_memory_MemAvailable_bytes/1024/1024" 2>/dev/null | python3 -c "
import sys, json
d=json.load(sys.stdin)['data']['result']
for r in sorted(d, key=lambda x: x['metric'].get('instance','')):
    print('    %-22s 可用内存 %.0f MB' % (r['metric'].get('instance',''), float(r['value'][1])))
" 2>/dev/null

echo
echo "  容器 CPU Top5:"
curl -s -m 8 "$PROM/api/v1/query?query=topk(5,container_cpu_usage_percent)" 2>/dev/null | python3 -c "
import sys, json
d=json.load(sys.stdin)['data']['result']
for r in d:
    n=r['metric'].get('name','')[:52]
    print('    %-54s %.2f%%' % (n, float(r['value'][1])))
" 2>/dev/null

echo
echo "################## G. 业务指标 ##################"
for m in "sum(rate(http_requests_total[5m]))" "sum(orders_created_total)" "sum(rate(http_requests_total{code=~\"5..\"}[5m]))" "history_quantile"; do
  curl -s -m 8 "$PROM/api/v1/query?query=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$m")" 2>/dev/null | python3 -c "
import sys, json
try:
  d=json.load(sys.stdin)['data']['result']
  if d: print('    %-40s = %s' % ('$m', d[0]['value'][1]))
except: pass
" 2>/dev/null
done
echo "COLLECT-DONE"
