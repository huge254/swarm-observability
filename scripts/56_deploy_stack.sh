#!/bin/bash
# manager：部署项目4 全栈到 Docker Swarm
set -u
STACK=order-observability
B=/opt/order-stack
REG=192.168.123.20:5000

echo "=================== [0] 环境前置检查 ==================="
echo "  SELinux: $(getenforce 2>/dev/null)"
echo "  firewalld: $(systemctl is-active firewalld 2>/dev/null)"
echo "  registry: $(curl -s -m 5 -o /dev/null -w '%{http_code}' http://$REG/v2/)"
echo "  swarm: $(docker info 2>/dev/null | grep -o 'Swarm: .*')"

echo
echo "=================== [1] 清理历史栈 ==================="
docker stack rm $STACK >/dev/null 2>&1
for i in $(seq 1 20); do
  n=$(docker stack ls --format '{{.Name}}' 2>/dev/null | grep -c "^$STACK$" || true)
  [ "$n" = "0" ] && break
  sleep 3
done
echo "  当前栈: $(docker stack ls 2>&1 | tail -n +2 | tr '\n' ' ')"
for c in $(docker config ls --format '{{.Name}}' 2>/dev/null | grep "^${STACK}_"); do
  docker config rm "$c" >/dev/null 2>&1
done
echo "  残留配置已清理"

echo
echo "=================== [2] 部署栈 ==================="
cd $B
docker stack deploy -c docker-compose.yml $STACK 2>&1 | sed 's/^/  /'

echo
echo "=================== [3] 等待收敛（最多 180s）==================="
for i in $(seq 1 18); do
  sleep 10
  echo "  [$(($i*10))s] $(docker stack services $STACK --format '{{.Name}}={{.Replicas}}' 2>/dev/null | tr '\n' ' ')"
  ok=$(docker stack services $STACK --format '{{.Replicas}}' 2>/dev/null | awk -F/ '$1==$2' | wc -l)
  all=$(docker stack services $STACK --format '{{.Name}}' 2>/dev/null | wc -l)
  if [ "$ok" = "$all" ] && [ "$all" != "0" ]; then
    echo "  全部服务就绪"
    break
  fi
done

echo
echo "=================== [4] 服务总览 ==================="
docker stack services $STACK 2>&1 | sed 's/^/  /'

echo
echo "=================== [5] 任务分布 ==================="
docker stack ps $STACK --format '  {{.Name}}  {{.Node}}  {{.CurrentState}}  {{.Error}}' 2>&1 | head -40
echo "DEPLOY-DONE"
