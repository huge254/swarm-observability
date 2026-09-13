#!/bin/bash
# worker1：把 redis_exporter 推入私有仓库
set -u
REG=192.168.123.20:5000
echo "===== $(hostname) 推送 redis_exporter ====="

SRC=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -i 'redis_exporter' | head -1)
echo "  源镜像: ${SRC:-未找到}"
if [ -z "$SRC" ]; then
  echo "  尝试拉取..."
  timeout 120 docker pull docker.1panel.live/oliver006/redis_exporter:v1.62.0 2>&1 | tail -2 | sed 's/^/    /'
  SRC=docker.1panel.live/oliver006/redis_exporter:v1.62.0
fi

docker tag "$SRC" $REG/redis-exporter:v1.62.0
docker push $REG/redis-exporter:v1.62.0 2>&1 | tail -2 | sed 's/^/  /'

echo
echo "  仓库目录:"
curl -s -m 8 http://$REG/v2/_catalog | tr ',' '\n' | sed 's/^/    /'
echo "REDIS-EXPORTER-PUSHED"
