#!/bin/bash
# 采集项：项目4、项目6 —— 告警端到端时延
# 用法：先注入故障，收到推送后运行本脚本，填入两个时间点
set -u

echo "端到端时延 = 从注入故障 → 到钉钉/企业微信收到推送 的时间"
echo "（包含 scrape interval + 规则评估 + for 时长 + Alertmanager 分组等待 + Webhook 推送）"
echo

read -r -p "注入故障的时间 (例 15:32:10): " T1
read -r -p "收到告警推送的时间 (例 15:33:02): " T2

t1=$(date -d "$T1" +%s 2>/dev/null || echo "")
t2=$(date -d "$T2" +%s 2>/dev/null || echo "")

if [ -n "$t1" ] && [ -n "$t2" ]; then
  echo
  echo "  端到端时延: $((t2 - t1)) 秒"
else
  echo "时间格式解析失败，请用 HH:MM:SS 重新输入"
fi

echo
echo "== 进阶：拆开测量更有说服力 =="
echo "  1) 检测时延：查 Alertmanager 中该告警的 startsAt 与注入时刻之差"
echo "  2) 通知时延：查推送到达时刻与 startsAt 之差"
echo "  3) 排查命令：curl -s $PROM/api/v1/alerts 查看 activeAt；Alertmanager UI 查看 startsAt"
echo
echo "写入简历格式示例：注入内存压力后 62 秒收到钉钉告警，告警清除与故障恢复同步"
