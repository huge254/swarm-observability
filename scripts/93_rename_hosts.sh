#!/bin/bash
# 项目2 主机名规范化：改为「两个英文单词」格式
#   .10 keepalived1 -> lb-master    .14 mysql1 -> db-master
#   .11 keepalived2 -> lb-backup    .15 mysql2 -> db-slave
#   .12 haproxy1    -> web-node1    .16 nfs    -> nfs-server
#   .13 haproxy2    -> web-node2
set -u
IP=$(hostname -I | awk '{print $1}')
OLD=$(hostname)

case "$IP" in
  192.168.123.10) NEW=lb-master  ;;
  192.168.123.11) NEW=lb-backup  ;;
  192.168.123.12) NEW=web-node1  ;;
  192.168.123.13) NEW=web-node2  ;;
  192.168.123.14) NEW=db-master  ;;
  192.168.123.15) NEW=db-slave   ;;
  192.168.123.16) NEW=nfs-server ;;
  *) echo "!! 未知节点 $IP"; exit 1 ;;
esac

echo "########## $IP : $OLD -> $NEW ##########"

echo "[1] 设置主机名"
hostnamectl set-hostname "$NEW" 2>&1 | sed 's/^/  /'
echo "  /etc/hostname     = $(cat /etc/hostname)"
echo "  hostname          = $(hostname)"
echo "  hostname -f       = $(hostname -f 2>/dev/null)"

echo
echo "[2] 重写 /etc/hosts 集群段"
cp -f /etc/hosts "/etc/hosts.bak.$(date +%Y%m%d%H%M%S)"
sed -Ei '/^192\.168\.123\.(10|11|12|13|14|15|16|100)[[:space:]]/d' /etc/hosts
cat >> /etc/hosts <<'EOF'
192.168.123.10   lb-master
192.168.123.11   lb-backup
192.168.123.12   web-node1
192.168.123.13   web-node2
192.168.123.14   db-master
192.168.123.15   db-slave
192.168.123.16   nfs-server
192.168.123.100  www.company.com oa.company.com
EOF
echo "  新 /etc/hosts:"
grep -E '192\.168\.123\.' /etc/hosts | sed 's/^/    /'

echo
echo "[3] HAProxy 后端标签同步改名（仅 LB 节点）"
if [ -f /etc/haproxy/haproxy.cfg ] && grep -q 'server web1 ' /etc/haproxy/haproxy.cfg; then
  cp -f /etc/haproxy/haproxy.cfg "/etc/haproxy/haproxy.cfg.bak.$(date +%Y%m%d%H%M%S)"
  sed -i -E \
    -e 's/server web1 192\.168\.123\.12/server web-node1 192.168.123.12/g' \
    -e 's/server web2 192\.168\.123\.13/server web-node2 192.168.123.13/g' \
    -e 's/server db1 192\.168\.123\.14/server db-master 192.168.123.14/g' \
    -e 's/server db2 192\.168\.123\.15/server db-slave 192.168.123.15/g' \
    /etc/haproxy/haproxy.cfg
  echo "  改后 server 行:"
  grep -nE '^\s*server\s' /etc/haproxy/haproxy.cfg | sed 's/^/    /'
  if haproxy -c -f /etc/haproxy/haproxy.cfg >/tmp/hac.log 2>&1; then
    echo "  配置校验: OK"
    systemctl reload haproxy && echo "  HAProxy 已 reload"
  else
    echo "  !! 配置校验失败，回滚"
    tail -3 /tmp/hac.log | sed 's/^/    /'
    cp -f $(ls -t /etc/haproxy/haproxy.cfg.bak.* | head -1) /etc/haproxy/haproxy.cfg
  fi
else
  echo "  （本节点无 HAProxy 或已是新标签）"
fi

echo
echo "[4] 服务状态复核"
for s in keepalived haproxy nginx mysqld nfs-server named; do
  st=$(systemctl is-active $s 2>/dev/null)
  case "$st" in
    active) echo "  $s = active" ;;
    "") ;;
    *) [ "$st" != "inactive" ] && [ "$st" != "unknown" ] && echo "  $s = $st" ;;
  esac
done
echo "RENAME-DONE"
