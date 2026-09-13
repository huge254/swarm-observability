#!/bin/bash
# worker 节点加入 Swarm 集群（令牌通过环境变量传入）
set -u
echo "===== $(hostname) 加入 Swarm ====="
TOKEN="${WORKER_TOKEN:?WORKER_TOKEN 未设置}"

if docker info 2>/dev/null | grep -q 'Swarm: active'; then
  echo "  已在 Swarm 集群中，状态:"
  docker info 2>/dev/null | grep -E 'Swarm:|Node Address|Is Manager' | sed 's/^/    /'
else
  docker swarm join --token "$TOKEN" 192.168.123.20:2377 2>&1 | sed 's/^/  /'
fi

echo
docker info 2>/dev/null | grep -E 'Swarm:|Node Address' | sed 's/^/  /'
echo "JOIN-DONE"
