#!/bin/bash
# 采集项：项目1 —— VIP 漂移耗时、业务请求成功率、业务中断时长
# 运行位置：能访问 VIP 的任意客户端（建议第三台机器）
# 用法：bash 01_vip_failover.sh <VIP> <URL路径> [采样次数]
set -u
VIP="${1:-192.168.10.100}"
URI="${2:-/}"
COUNT="${3:-100}"
INTERVAL=0.2
URL="http://${VIP}${URI}"
LOG="/tmp/vip_probe_$(date +%H%M%S).log"

echo "探测目标: $URL   采样次数: $COUNT   间隔: ${INTERVAL}s"
echo
echo "== 1) 基线检查（连续 5 次，应全部返回 200）=="
for i in $(seq 1 5); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$URL")
  echo "  baseline $i -> $code"
done

echo
echo "== 2) 漂移耗时测量（需要两个终端配合）=="
echo "  终端A（本机）：先执行下面这条，记录备节点接管 VIP 的时刻"
echo "      date +%s.%N; while ! ip -4 addr show | grep -q '${VIP}'; do sleep 0.05; done; date +%s.%N"
echo "  终端B（主节点）：先执行 date +%s.%N 记录停止前时刻，再执行 systemctl stop nginx"
echo "  → 漂移耗时 = 备节点看到 VIP 的时刻 − 主节点停止服务的时刻"
echo
read -r -p "按回车开始采样（采样期间请立刻在另一终端停止主节点 Nginx）... "

echo
ok=0; fail=0; first_fail=""; last_fail=""
for i in $(seq 1 "$COUNT"); do
  ts=$(date +%s.%N)
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$URL")
  if [ "$code" = "200" ]; then
    ok=$((ok+1))
  else
    fail=$((fail+1))
    [ -z "$first_fail" ] && first_fail="$ts"
    last_fail="$ts"
  fi
  printf '%s %s\n' "$ts" "$code" >> "$LOG"
  sleep "$INTERVAL"
done

echo
echo "== 3) 结果 =="
echo "  总请求: $COUNT   成功: $ok   失败: $fail"
awk -v ok="$ok" -v n="$COUNT" 'BEGIN{printf "  业务请求成功率: %.1f%%\n", ok*100/n}'
if [ -n "$first_fail" ]; then
  awk -v a="$first_fail" -v b="$last_fail" 'BEGIN{printf "  失败窗口（约等于业务中断时长）: %.1f 秒\n", b-a}'
else
  echo "  未出现失败请求：说明切换过程中业务无中断，成功率可直接写 100%"
fi
echo "  原始采样日志: $LOG"
echo
echo "写入简历格式示例：VIP 漂移耗时 1.2 秒，期间业务请求成功率 100%（采样 100 次）"
