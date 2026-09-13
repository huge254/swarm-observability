#!/bin/bash
# 项目4 节点基础配置：主机名 + 集群 hosts + 静态IP + 停用宿主层监控（端口让给容器版）
set -u
NODE_NAME="${NODE_NAME:?}"
NODE_IP="${NODE_IP:?}"

echo "=================== [0] 配置前 ==================="
echo "主机名: $(hostname)   IP: $(ip -4 addr show ens160 | awk '/inet /{print $2}')"

echo
echo "=================== [1] 主机名 ==================="
hostnamectl set-hostname "$NODE_NAME"
echo "新主机名: $(hostname)"

echo
echo "=================== [2] 集群 hosts ==================="
cat > /etc/hosts <<'EOF'
127.0.0.1   localhost localhost.localdomain
::1         localhost localhost.localdomain
192.168.123.20   p4-manager manager
192.168.123.21   p4-worker1 worker1
192.168.123.22   p4-worker2 worker2
192.168.123.23   p4-worker3 worker3
192.168.123.24   p4-worker4 worker4
EOF
cat /etc/hosts

echo
echo "=================== [3] 静态 IP（持久化）==================="
CONN=$(nmcli -t -f NAME,DEVICE connection show --active | grep -v ':lo' | head -n1 | cut -d: -f1)
nmcli connection modify "$CONN" \
  ipv4.method manual \
  ipv4.addresses "${NODE_IP}/24" \
  ipv4.gateway 192.168.123.2 \
  ipv4.dns "192.168.123.20,223.5.5.5" \
  connection.autoconnect yes
nmcli connection show "$CONN" | grep -E 'ipv4.method|ipv4.addresses|ipv4.gateway'

echo
echo "=================== [4] 清理订阅报错 ==================="
[ -f /etc/yum.repos.d/redhat.repo ] && mv -f /etc/yum.repos.d/redhat.repo /etc/yum.repos.d/redhat.repo.disabled && echo "已禁用 redhat.repo"
findmnt /mnt >/dev/null 2>&1 || mount /dev/sr0 /mnt 2>/dev/null
dnf repolist 2>/dev/null | tail -4

echo
echo "=================== [5] 停用宿主层 Prometheus/Grafana（端口 9090/3000 让给容器版），保留 node_exporter ==================="
systemctl disable --now prometheus grafana >/dev/null 2>&1
for s in prometheus grafana node_exporter; do
  printf '  %-14s %s\n' "$s" "$(systemctl is-active $s 2>/dev/null)"
done
ss -lntp 2>/dev/null | grep -E ':9090|:3000|:9100' | awk '{print "  占用端口: "$4}'

echo
echo "=================== [6] 安全基线 ==================="
echo "SELinux: $(getenforce)  |  配置: $(grep -E '^SELINUX=' /etc/selinux/config)"
echo "firewalld: $(systemctl is-active firewalld 2>/dev/null)"
echo "（Docker 与 firewalld 会争抢 iptables 规则，本实验保留 firewalld 关闭状态）"

echo
echo "=================== [7] 重启验证持久化 ==================="
( setsid nohup bash -c 'sleep 8; systemctl reboot' >/dev/null 2>&1 & )
echo "DONE-REBOOT-TRIGGERED"
