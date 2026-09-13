#!/bin/bash
# worker1：把 alertmanager / loki 直接推到 manager 的私有仓库（免中转）
set -u
echo "===== $(hostname) 推送中间件镜像 ====="
REG=192.168.123.20:5000

echo "[1] 仓库连通性"
curl -s -m 5 -o /dev/null -w "  http_code=%{http_code}\n" http://$REG/v2/

push_one() {
  SRC="$1"; DST="$2"
  echo
  echo "[$DST]"
  if ! docker image inspect "$SRC" >/dev/null 2>&1; then
    echo "  源镜像不存在: $SRC"
    return
  fi
  docker tag "$SRC" "$REG/$DST"
  docker push "$REG/$DST" 2>&1 | tail -2 | sed 's/^/  /'
}

push_one docker.1panel.live/prom/alertmanager:v0.27.0 alertmanager:local
push_one hub.rat.dev/prom/alertmanager:v0.27.0      alertmanager:local
push_one docker.1panel.live/grafana/loki:2.9.0      loki:local
push_one docker.1panel.live/library/registry:2      registry:local

echo
echo "=================== 仓库目录 ==================="
curl -s -m 10 "http://$REG/v2/_catalog" | tr ',' '\n' | sed 's/^/  /'
echo
echo "WORKER1-PUSH-DONE"
