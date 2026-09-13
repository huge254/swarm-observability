#!/bin/bash
# manager：给订单服务镜像补 cryptography（PyMySQL 连接 MySQL 8.4 caching_sha2_password 所需），产出 v3
set -u
REG=192.168.123.20:5000
PIP="--index-url https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com --quiet"

echo "=================== 构建 order-api:v3 ==================="
docker rm -f bld3 >/dev/null 2>&1
docker run -d --name bld3 $REG/order-api:v2 sleep 1200 >/dev/null 2>&1
sleep 2
echo "  容器: $(docker ps --filter name=bld3 --format '{{.Status}}')"

echo "  安装 cryptography ..."
docker exec bld3 /usr/bin/pip3 install $PIP cryptography 2>&1 | tail -2 | sed 's/^/    /'

echo "  验证依赖 ..."
docker exec bld3 /usr/bin/python3 -c "import flask,gunicorn,pymysql,redis,prometheus_client,cryptography;print('    all-deps-ok')" 2>&1 | tail -2

echo "  提交 v3 ..."
docker commit \
  --change 'WORKDIR /app' \
  --change 'ENV PYTHONUNBUFFERED=1' \
  --change 'EXPOSE 8000' \
  --change 'CMD ["/usr/bin/python3","-m","gunicorn","--workers","2","--threads","4","--timeout","30","--bind","0.0.0.0:8000","--access-logfile","-","--error-logfile","-","app:app"]' \
  bld3 $REG/order-api:v3 >/dev/null 2>&1
docker rm -f bld3 >/dev/null 2>&1
docker images --format '  {{.Repository}}:{{.Tag}} {{.Size}}' | grep 'order-api'

echo
echo "  推送 ..."
docker push $REG/order-api:v3 2>&1 | tail -1 | sed 's/^/    /'

echo
echo "  本地镜像清单:"
docker images --format '  {{.Repository}}:{{.Tag}} {{.Size}}' | grep '192.168.123.20:5000' | sort
echo "ORDER-API-V3-DONE"
