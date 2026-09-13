#!/bin/bash
# manager：启动私有镜像仓库 registry:2（供 Swarm 各节点拉取自建镜像）
set -u
echo "===== $(hostname) 私有仓库部署 ====="

echo "[1] 加载 registry:2 镜像"
if docker images --format '{{.Repository}}:{{.Tag}}' | grep -qx 'registry:2'; then
  echo "  本机已有 registry:2"
else
  docker load -i /tmp/registry2.tar 2>&1 | tail -3 | sed 's/^/  /'
fi
docker images | grep -i registry | sed 's/^/  /'

echo
echo "[2] 启动 registry 容器"
docker rm -f registry >/dev/null 2>&1
mkdir -p /opt/registry-data
docker run -d --name registry --restart=always \
  -p 5000:5000 \
  -v /opt/registry-data:/var/lib/registry \
  registry:2 >/dev/null 2>&1
sleep 5
docker ps --filter name=registry --format '  {{.Names}} | {{.Status}} | {{.Ports}}'

echo
echo "[3] 仓库 API 验证"
curl -s -m 5 -o /dev/null -w "  本机 http_code=%{http_code}\n" http://192.168.123.20:5000/v2/
echo -n "  catalog: "
curl -s -m 5 http://192.168.123.20:5000/v2/_catalog 2>/dev/null
echo

echo
echo "[4] 防火墙放通 5000"
if systemctl is-active firewalld >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=5000/tcp >/dev/null 2>&1
  firewall-cmd --reload >/dev/null 2>&1
  echo "  firewalld 已放通 5000/tcp -> $(firewall-cmd --list-ports)"
else
  echo "  firewalld 未运行"
fi
echo "REGISTRY-DONE"
