#!/bin/bash
# 项目4：安装 Docker CE 并配置镜像加速
set -u

echo "=================== [1] 配置 Docker CE 源（阿里云）==================="
dnf -y install dnf-plugins-core >/dev/null 2>&1
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/rhel/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
echo "repo 文件已就绪"
dnf repolist 2>/dev/null | grep -i docker
echo "--- 可安装版本 ---"
dnf -q list --available docker-ce 2>/dev/null | tail -3

echo
echo "=================== [2] 安装 Docker CE ==================="
dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /tmp/docker_install.log 2>&1
echo "安装退出码: $?"
tail -6 /tmp/docker_install.log
rpm -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>&1

echo
echo "=================== [3] daemon.json（含实测可达的镜像加速）==================="
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
    "https://docker.xuanyuan.me",
    "https://docker.1panel.live",
    "https://hub.rat.dev"
  ],
  "live-restore": true
}
EOF
cat /etc/docker/daemon.json

echo
echo "=================== [4] 启动 Docker ==================="
systemctl enable --now docker >/dev/null 2>&1
sleep 6
echo "docker 服务: $(systemctl is-active docker)"
docker version --format 'Server 版本={{.Server.Version}}  Client 版本={{.Client.Version}}' 2>&1
docker info 2>/dev/null | grep -E 'Storage Driver|Cgroup Driver|Docker Root Dir' | sed 's/^/  /'

echo
echo "=================== [5] 镜像拉取实测 ==================="
echo "--- 小镜像 hello-world ---"
timeout 150 docker pull hello-world 2>&1 | tail -3
echo "--- alpine ---"
timeout 180 docker pull alpine:latest 2>&1 | tail -3
echo "--- 已本地镜像 ---"
docker images 2>/dev/null

echo
echo "=================== [6] Swarm 相关内核参数 ==================="
sysctl net.bridge.bridge-nf-call-iptables 2>/dev/null
sysctl net.ipv4.ip_forward
echo "DOCKER-READY"
