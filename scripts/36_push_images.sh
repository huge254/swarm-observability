#!/bin/bash
# manager：把所有本地自建镜像推入私有仓库
set -u
echo "===== $(hostname) 推送镜像到私有仓库 ====="

REG=192.168.123.20:5000
IMGS=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep "^$REG/" | sort)
echo "待推送镜像:"
echo "$IMGS" | sed 's/^/  /'
echo

for i in $IMGS; do
  echo "=== push $i ==="
  docker push "$i" 2>&1 | tail -2 | sed 's/^/  /'
done

echo
echo "=================== 仓库目录 ==================="
curl -s -m 10 "http://$REG/v2/_catalog" | tr ',' '\n' | sed 's/^/  /'
echo
echo "PUSH-DONE"
