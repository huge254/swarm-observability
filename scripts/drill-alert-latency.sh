#!/bin/bash
# 告警闭环演练（第二轮）：D2 复测 + D3 错误率 + D4 延迟
# 脱离 SSH 会话运行：nohup bash drill2.sh &
set -u
STACK=order-observability
PROM=http://127.0.0.1:9090
RECV=http://127.0.0.1:8080/alerts
OUT=/opt/order-stack/drill/result2.txt
LOADGEN=/opt/order-stack/drill/loadgen.py

log() { echo "$@" >> $OUT; echo "$@" ; }

prom_firing() {
  curl -s -m 6 "$PROM/api/v1/alerts" 2>/dev/null | python3 -c "
import sys, json
try: d = json.load(sys.stdin)
except Exception: sys.exit(1)
for a in d.get('data',{}).get('alerts',[]):
    if a['labels'].get('alertname')=='$1' and a.get('state')=='firing':
        sys.exit(0)
sys.exit(1)
"
}

recv_firing() {
  curl -s -m 6 "$RECV" 2>/dev/null | python3 -c "
import sys, json
try: d = json.load(sys.stdin)
except Exception: sys.exit(1)
for i in d.get('items',[]):
    if i.get('alertname')=='$1' and i.get('status')=='firing':
        sys.exit(0)
sys.exit(1)
"
}

wait_for() {
  local fn=$1 name=$2 timeout=$3
  local t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt $timeout ]; do
    if $fn "$name"; then echo $(( $(date +%s) - t0 )); return 0; fi
    sleep 3
  done
  echo -1
}

run_case() {
  local cname="$1" alert="$2" inject="$3" recover="$4" note="$5"
  log ""
  log "==================================================================="
  log "场景：$cname"
  log "期望告警：$alert"
  log "故障注入：$inject"
  log "备注：$note"
  log "-------------------------------------------------------------------"
  local t0=$(date +%s)
  bash -c "$inject" >/dev/null 2>&1
  log "  注入时刻：$(date '+%H:%M:%S')"

  local d=$(wait_for prom_firing "$alert" 300)
  if [ "$d" = "-1" ]; then
    log "  [FAIL] 300s 内 Prometheus 未检测到告警"
    bash -c "$recover" >/dev/null 2>&1
    return
  fi
  log "  ① Prometheus 检测到告警：+${d}s"

  local n=$(wait_for recv_firing "$alert" 180)
  if [ "$n" = "-1" ]; then
    log "  [WARN] 检测到了，但 180s 内未触达接收端"
  else
    log "  ② 告警触达接收端：+$(( d + n ))s  （通知环节耗时 ${n}s）"
    log "  ===> 端到端时延：$(( d + n )) 秒"
  fi

  log "  开始恢复 ..."
  bash -c "$recover" >/dev/null 2>&1
  local t1=$(date +%s)
  while [ $(( $(date +%s) - t1 )) -lt 300 ]; do
    if ! prom_firing "$alert"; then
      log "  ③ 告警已恢复：+$(( $(date +%s) - t0 ))s"
      break
    fi
    sleep 5
  done
}

log "==================================================================="
log "项目4 告警闭环演练报告（第二轮，接收端已加内存兜底）"
log "开始时间：$(date '+%Y-%m-%d %H:%M:%S')"
log "==================================================================="

# ---------------- D2 复测：Redis 宕机 ----------------
run_case "D2 Redis(Valkey) 宕机（复测）" "RedisDown" \
  "docker service scale ${STACK}_redis=0" \
  "docker service scale ${STACK}_redis=1" \
  "critical 级；接收端已改为内存兜底，Redis 故障不影响告警记录"

# ---------------- D3：业务错误率 ----------------
log ""
log "D3 准备：启动错误注入负载（后台 300s）"
nohup python3 $LOADGEN --url http://127.0.0.1:8000 --concurrency 15 --duration 300 --mode error \
  > /tmp/loadgen_error.log 2>&1 &
sleep 3
run_case "D3 订单服务 5xx 错误率飙升" "ApiHighErrorRate" \
  "sleep 1" \
  "pkill -f 'loadgen.py.*--mode error'" \
  "critical 级；/debug/error 制造持续 5xx"

# ---------------- D4：业务延迟 ----------------
sleep 20
log ""
log "D4 准备：启动延迟注入负载（后台 300s）"
nohup python3 $LOADGEN --url http://127.0.0.1:8000 --concurrency 12 --duration 300 --mode slow --slow-ms 1500 \
  > /tmp/loadgen_slow.log 2>&1 &
sleep 3
run_case "D4 订单服务 P95 延迟劣化" "ApiHighLatencyP95" \
  "sleep 1" \
  "pkill -f 'loadgen.py.*--mode slow'" \
  "warning 级；/debug/slow 注入 1.5s 延迟"

pkill -f loadgen.py >/dev/null 2>&1
log ""
log "==================================================================="
log "第二轮演练结束：$(date '+%Y-%m-%d %H:%M:%S')"
log "==================================================================="
echo "DRILL2-DONE" >> $OUT
