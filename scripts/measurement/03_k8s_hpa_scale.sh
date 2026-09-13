#!/bin/bash
# 采集项：项目5 —— HPA 扩容/缩容耗时、QPS
# 用法：bash 03_k8s_hpa_scale.sh <namespace> <label值>
set -u
NS="${1:-default}"
APP="${2:-web}"

echo "== 1) 当前状态 =="
kubectl get hpa -n "$NS"
echo
kubectl get pods -n "$NS" -l app="$APP" -o wide

echo
echo "== 2) 开始观测（每 5 秒一行，共 5 分钟；请立刻在另一终端启动压测）=="
echo "  压测示例：locust -f locustfile.py --headless -u 200 -r 20 --run-time 5m"
echo "  记录方法：replicas 从初始值涨到最大值的第一行时间 − 压测开始时间 = 扩容耗时"
echo "            压测停止后 replicas 回落到初始值的第一行时间 − 停止时间 = 缩容耗时"
echo

for i in $(seq 1 60); do
  n=$(kubectl get pods -n "$NS" -l app="$APP" --no-headers 2>/dev/null | grep -c Running)
  line=$(kubectl get hpa -n "$NS" --no-headers 2>/dev/null | head -1)
  printf '%s  running_pods=%s  | %s\n' "$(date +%H:%M:%S)" "$n" "$line"
  sleep 5
done

echo
echo "== 3) QPS 从哪里取 =="
echo "  Locust 结束后的报告里有 Requests/s（总 QPS）与各接口 P95"
echo "  扩容前 QPS 取压测前 30 秒的平均值，扩容后 QPS 取副本数稳定后的平均值"
echo
echo "写入简历格式示例：HPA 基于 CPU 60%，副本 2 → 6，扩容耗时 45 秒，QPS 由 320 提升至 890"
