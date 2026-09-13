#!/bin/bash
# MySQL 8.4 单实例启动脚本：首次启动自动初始化数据目录并导入 schema
set -e
DATADIR=/var/lib/mysql
SOCK=/var/run/mysqld/mysqld.sock
LOG=/var/log/mysql/error.log

mkdir -p "$DATADIR" /var/run/mysqld /var/log/mysql
chown -R mysql:mysql "$DATADIR" /var/run/mysqld /var/log/mysql

if [ ! -d "$DATADIR/mysql" ]; then
  echo "[entrypoint] 首次启动，初始化数据目录 ..."
  mysqld --initialize-insecure --user=mysql --datadir="$DATADIR"
  echo "[entrypoint] 数据目录初始化完成"
fi

echo "[entrypoint] 启动 mysqld（加载 /etc/mysql-init/init.sql）..."
exec mysqld \
  --user=mysql \
  --datadir="$DATADIR" \
  --socket="$SOCK" \
  --pid-file=/var/run/mysqld/mysqld.pid \
  --bind-address=0.0.0.0 \
  --port=3306 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci \
  --max-connections=300 \
  --slow-query-log=1 \
  --long-query-time=1 \
  --log-error="$LOG" \
  --init-file=/etc/mysql-init/init.sql
