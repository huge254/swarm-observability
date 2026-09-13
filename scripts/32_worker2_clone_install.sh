#!/bin/bash
# worker2：离线复刻 Docker 安装（从 tar 解包）
set -u
echo "===== $(hostname) 离线复刻 Docker ====="

TAR=/tmp/docker_pkg.tar.gz
if [ ! -s "$TAR" ]; then
  echo "!! 找不到 $TAR"
  ls -lh /tmp/*.tar.gz 2>/dev/null | sed 's/^/  /'
  exit 1
fi
echo "  包大小: $(ls -lh $TAR | awk '{print $5}')"

echo
echo "=================== [1] docker 用户组 ==================="
if getent group docker >/dev/null; then
  echo "  已存在: $(getent group docker)"
else
  groupadd -g 991 docker && echo "  已创建: $(getent group docker)"
fi

echo
echo "=================== [2] 解包到 / ==================="
tar -xzf $TAR -C / 2>/dev/null
echo "  退出码: $?"

echo
echo "=================== [3] SELinux 标签恢复 ==================="
if command -v restorecon >/dev/null; then
  restorecon -R /usr/bin/docker /usr/bin/dockerd /usr/bin/containerd /usr/bin/runc /usr/bin/ctr /usr/libexec/docker /usr/lib/systemd/system/docker.service /usr/lib/systemd/system/docker.socket /usr/lib/systemd/system/containerd.service 2>/dev/null
  echo "  restorecon 完成"
else
  echo "  (无 restorecon)"
fi

echo
echo "=================== [4] 二进制确认 ==================="
for b in /usr/bin/docker /usr/bin/dockerd /usr/bin/containerd /usr/bin/runc /usr/bin/ctr; do
  if [ -x "$b" ]; then echo "  OK  $b  ($($b --version 2>&1 | head -1))"; else echo "  MISSING  $b"; fi
done
ls -l /usr/libexec/docker/cli-plugins/ 2>/dev/null | sed 's/^/  /'

echo
echo "=================== [5] daemon.json（无 live-restore）==================="
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "3"
  },
  "registry-mirrors": [
    "https://docker.1panel.live",
    "https://hub.rat.dev"
  ]
}
EOF
cat /etc/docker/daemon.json | sed 's/^/  /'

echo
echo "=================== [6] 启动服务 ==================="
systemctl daemon-reload
systemctl enable --now containerd >/dev/null 2>&1
sleep 3
echo "  containerd: $(systemctl is-active containerd)"
systemctl enable --now docker >/dev/null 2>&1
sleep 8
echo "  docker: $(systemctl is-active docker)"
echo "  server 版本: $(docker version --format '{{.Server.Version}}' 2>&1)"
docker info 2>/dev/null | grep -E 'Storage Driver|Cgroup Driver|Live Restore|Swarm:' | sed 's/^/  /'

echo
echo "=================== [7] 运行验证 ==================="
docker run --rm hello-world 2>&1 | head -5 | sed 's/^/  /'
echo
echo "WORKER2-CLONE-DONE"
