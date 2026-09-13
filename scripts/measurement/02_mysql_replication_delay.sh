#!/bin/bash
# 采集项：项目2、项目7 —— MySQL 主从复制延迟
# 用法：bash 02_mysql_replication_delay.sh <从库IP> <用户> <密码>
set -u
HOST="${1:-127.0.0.1}"
USER="${2:-root}"
PASS="${3:-}"

if [ -n "$PASS" ]; then
  MYSQL=(mysql -h"$HOST" -u"$USER" -p"$PASS")
else
  MYSQL=(mysql -h"$HOST" -u"$USER")
fi

echo "== 1) 复制状态（MySQL 8 也可用 SHOW REPLICA STATUS）=="
"${MYSQL[@]}" -e "SHOW SLAVE STATUS\G" 2>/dev/null | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master|Relay_Master_Log_File|Exec_Master_Log_Pos|Last_IO_Error|Last_SQL_Error"

echo
echo "== 2) 连续采样 10 次延迟（单位：秒，NULL 表示复制中断或未采样到）=="
for i in $(seq 1 10); do
  v=$("${MYSQL[@]}" -N -B -e "SHOW SLAVE STATUS\G" 2>/dev/null | awk -F': ' '/Seconds_Behind_Master/{print $2}')
  echo "  sample $i: ${v:-NULL}"
  sleep 2
done

echo
echo "== 3) 压测下的峰值延迟（可选，更有说服力）=="
echo "  另开终端制造写流量：sysbench oltp_write_only --mysql-host=<主库IP> --mysql-user=$USER --tables=10 --table-size=10000 --threads=8 --time=120 run"
echo "  同时重跑本脚本，记录峰值 Seconds_Behind_Master"
echo
echo "写入简历格式示例：空闲复制延迟 <1 秒，sysbench 写压测下峰值 320 ms"
