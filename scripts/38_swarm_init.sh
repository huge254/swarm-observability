#!/bin/bash
# manager：初始化 Docker Swarm 并输出 worker 加入令牌
set -u
echo "===== $(hostname) Swarm 初始化 ====="

echo "[1] 初始化"
if docker info 2>/dev/null | grep -q 'Swarm: active'; then
  echo "  已是 Swarm 节点，跳过"
else
  docker swarm init --advertise-addr 192.168.123.20 2>&1 | tail -8 | sed 's/^/  /'
fi

echo
echo "[2] 集群状态"
docker info 2>/dev/null | grep -E 'Swarm:|Is Manager|Nodes:|Managers:' | sed 's/^/  /'
echo "  节点列表:"
docker node ls 2>&1 | sed 's/^/    /'

echo
echo "[3] worker 加入令牌"
WT=$(docker swarm join-token -q worker 2>/dev/null)
echo "  WORKER_TOKEN=$WT"
echo "$WT" > /root/.swarm_worker_token

echo
echo "[4] manager 令牌（备用）"
docker swarm join-token -q manager 2>/dev/null | sed 's/^/  MANAGER_TOKEN=/'

echo
echo "[5] 节点标签规划"
cat <<'EOF'
  p4-manager  -> 监控栈（prometheus / grafana / alertmanager）+ 私有仓库
  p4-worker1  -> 订单服务副本
  p4-worker2  -> MySQL
  p4-worker3  -> Redis(valkey) + 订单服务副本 + 告警接收端
  p4-worker4  -> 日志/备用
EOF
echo "SWARM-INIT-DONE"
