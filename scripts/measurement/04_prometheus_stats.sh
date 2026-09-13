#!/bin/bash
# 采集项：项目4、项目6 —— 采集目标数、告警规则条数、firing 告警数、看板数
# 用法：bash 04_prometheus_stats.sh <Prometheus地址> [Grafana地址]
set -u
PROM="${1:-http://127.0.0.1:9090}"
GRAFANA="${2:-http://127.0.0.1:3000}"

echo "== 1) 采集目标数与健康状态 =="
curl -s "$PROM/api/v1/targets?state=active" | python3 -c '
import sys, json, collections
d = json.load(sys.stdin)["data"]["activeTargets"]
print("  active targets:", len(d))
print("  health:", dict(collections.Counter(t["health"] for t in d)))
print("  jobs:", sorted({t["labels"].get("job", "?") for t in d}))
' 2>/dev/null || echo "  解析失败：确认 Prometheus 地址与 python3 是否可用"

echo
echo "== 2) 告警规则条数（按规则文件统计）=="
find / -name "*.rules.yml" -o -name "*.rules.yaml" 2>/dev/null | while read -r f; do
  n=$(grep -cE "^[[:space:]]*-[[:space:]]*alert:" "$f" 2>/dev/null)
  echo "  $n 条  $f"
done

echo
echo "== 3) 当前 firing 告警数 =="
curl -s "$PROM/api/v1/alerts" | python3 -c '
import sys, json
a = json.load(sys.stdin)["data"]["alerts"]
print("  firing:", len(a))
for x in a[:10]:
    print("   -", x["labels"].get("alertname"))
' 2>/dev/null || echo "  解析失败"

echo
echo "== 4) Grafana 看板数量 =="
echo "  在 Grafana 主机执行（把 密码 换成你的）："
echo "  curl -s -u admin:密码 \"$GRAFANA/api/search?type=dash-db\" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))'"
echo
echo "写入简历格式示例：接入 8 个采集目标，编写 12 条告警规则，覆盖 4 类场景"
