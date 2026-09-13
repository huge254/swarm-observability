#!/bin/bash
# 构建 order-api / webhook-receiver 镜像（基于 rhel10-app:local 补装依赖与代码）
set -u
REG=192.168.123.20:5000
BASE=$REG/rhel10-app:local
PIP="--index-url https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com --quiet"

echo "=================== [1] 订单服务镜像 order-api:v2 ==================="
docker rm -f bld >/dev/null 2>&1
docker run -d --name bld "$BASE" sleep 1800 >/dev/null 2>&1
echo "  基础容器: $(docker ps --filter name=bld --format '{{.Status}}')"

echo "  安装依赖..."
docker exec bld /usr/bin/pip3 install $PIP flask gunicorn pymysql redis prometheus-client 2>&1 | tail -3 | sed 's/^/    /'

echo "  复制应用代码..."
docker exec bld mkdir -p /app
docker cp /opt/order-api/app.py     bld:/app/app.py
docker cp /opt/order-api/init.sql   bld:/app/init.sql
docker exec bld ls -l /app | sed 's/^/    /'

echo "  验证依赖..."
docker exec bld /usr/bin/python3 -c "import flask,gunicorn,pymysql,redis,prometheus_client;print('    deps-ok')" 2>&1 | tail -2

echo "  提交镜像..."
docker commit \
  --change 'WORKDIR /app' \
  --change 'ENV PYTHONUNBUFFERED=1' \
  --change 'EXPOSE 8000' \
  --change 'CMD ["/usr/bin/python3","-m","gunicorn","--workers","2","--threads","4","--timeout","30","--bind","0.0.0.0:8000","--access-logfile","-","--error-logfile","-","app:app"]' \
  bld $REG/order-api:v2 >/dev/null 2>&1
echo "    -> $(docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep 'order-api:v2')"
docker rm -f bld >/dev/null 2>&1

echo
echo "=================== [2] 告警接收端镜像 webhook-receiver:v2 ==================="
docker rm -f bld2 >/dev/null 2>&1
docker run -d --name bld2 "$BASE" sleep 1800 >/dev/null 2>&1
echo "  安装依赖..."
docker exec bld2 /usr/bin/pip3 install $PIP flask redis gunicorn 2>&1 | tail -2 | sed 's/^/    /'
echo "  复制代码..."
docker exec bld2 mkdir -p /app
docker cp /opt/order-stack/webhook/receiver.py bld2:/app/receiver.py
docker exec bld2 /usr/bin/python3 -c "import sys;sys.path.insert(0,'/app');import receiver;print('    import-ok')" 2>&1 | tail -2
echo "  提交镜像..."
docker commit \
  --change 'WORKDIR /app' \
  --change 'ENV PYTHONUNBUFFERED=1' \
  --change 'EXPOSE 8080' \
  --change 'CMD ["/usr/bin/python3","-m","gunicorn","--workers","1","--bind","0.0.0.0:8080","receiver:app"]' \
  bld2 $REG/webhook-receiver:v2 >/dev/null 2>&1
echo "    -> $(docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep 'webhook-receiver:v2')"
docker rm -f bld2 >/dev/null 2>&1

echo
echo "=================== [3] 推送新镜像 ==================="
for i in $REG/order-api:v2 $REG/webhook-receiver:v2; do
  echo "  push $i"
  docker push "$i" 2>&1 | tail -1 | sed 's/^/    /'
done

echo
echo "=================== [4] 仓库目录 ==================="
curl -s -m 8 http://$REG/v2/_catalog | tr ',' '\n' | sed 's/^/  /'
echo "REBUILD-DONE"
