#!/bin/bash
# worker2 补装 Docker CE（去掉 live-restore，避免与 Swarm 冲突）
set -u
echo "===== $(hostname) 补装 Docker ====="

echo "=================== [1] 配置 Docker CE 源（阿里云）==================="
dnf -y install dnf-plugins-core >/dev/null 2>&1
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/rhel/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
echo "repo: $(ls /etc/yum.repos.d/docker-ce.repo 2>/dev/null || echo FAILED)"
dnf repolist 2>/dev/null | grep -i docker | sed 's/^/  /'

echo
echo "=================== [2] 安装 Docker CE ==================="
dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /tmp/docker_install.log 2>&1
echo "安装退出码: $?"
tail -5 /tmp/docker_install.log | sed 's/^/  /'
rpm -q docker-ce docker-ce-cli containerd.io 2>&1 | sed 's/^/  /'

echo
echo "=================== [3] daemon.json（无 live-restore）==================="
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
echo "=================== [4] 启动 Docker ==================="
systemctl enable --now docker >/dev/null 2>&1
sleep 8
echo "  docker 服务: $(systemctl is-active docker)"
echo "  server 版本: $(docker version --format '{{.Server.Version}}' 2>&1)"
docker info 2>/dev/null | grep -E 'Storage Driver|Cgroup Driver|Live Restore|Swarm:' | sed 's/^/  /'

echo
echo "=================== [5] 小镜像拉取验证 ==================="
timeout 150 docker pull alpine:latest 2>&1 | tail -2 | sed 's/^/  /'

echo
echo "WORKER2-DOCKER-READY"
