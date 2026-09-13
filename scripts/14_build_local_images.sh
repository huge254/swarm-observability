#!/bin/bash
# 用本地 rootfs + 静态二进制构建项目4 所需的全部镜像（零外网下载）
set -u

REPOS=/opt/img/repos
REG=192.168.123.20:5000
OPTS="--releasever=10 --nogpgcheck --setopt=reposdir=$REPOS --setopt=plugins=0 --setopt=install_weak_deps=False --setopt=tsflags=nodocs"
PYDIR=/usr/local/lib/python3.12/site-packages
PYMIRROR="-i https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com"

findmnt /mnt >/dev/null 2>&1 || mount /dev/sr0 /mnt 2>/dev/null
mkdir -p /opt/img

echo "=================== [1] 重建基础 rootfs ==================="
rm -rf /opt/img/rfs-base
mkdir -p /opt/img/rfs-base
dnf -y --installroot=/opt/img/rfs-base $OPTS install \
    bash coreutils glibc-common shadow-utils tzdata procps-ng > /tmp/b1.log 2>&1
echo "退出码 $? / 大小 $(du -sh /opt/img/rfs-base | cut -f1)"
mkdir -p /opt/img/rfs-base/proc /opt/img/rfs-base/sys /opt/img/rfs-base/dev \
         /opt/img/rfs-base/tmp /opt/img/rfs-base/etc/ssl/certs

echo
echo "=================== [2] Prometheus 镜像 ==================="
rm -rf /opt/img/rfs-prom
cp -al /opt/img/rfs-base /opt/img/rfs-prom
mkdir -p /opt/img/rfs-prom/usr/local/bin /opt/img/rfs-prom/prometheus /opt/img/rfs-prom/etc/prometheus/rules
cp /opt/monitor/prometheus/prometheus /opt/img/rfs-prom/usr/local/bin/prometheus
tar -C /opt/img/rfs-prom -c . 2>/dev/null | docker import - $REG/prometheus:local >/dev/null 2>&1
docker run --rm $REG/prometheus:local /usr/local/bin/prometheus --version 2>&1 | head -2

echo
echo "=================== [3] Grafana 镜像 ==================="
rm -rf /opt/img/rfs-graf
cp -al /opt/img/rfs-base /opt/img/rfs-graf
mkdir -p /opt/img/rfs-graf/usr/share/grafana
cp -a /opt/monitor/grafana/bin /opt/monitor/grafana/public /opt/monitor/grafana/conf /opt/img/rfs-graf/usr/share/grafana/ 2>/dev/null
mkdir -p /opt/img/rfs-graf/var/lib/grafana /opt/img/rfs-graf/var/log/grafana
tar -C /opt/img/rfs-graf -c . 2>/dev/null | docker import - $REG/grafana:local >/dev/null 2>&1
docker run --rm $REG/grafana:local /usr/share/grafana/bin/grafana server --version 2>&1 | head -2
echo "镜像大小: $(docker image inspect $REG/grafana:local --format '{{.Size}}' 2>/dev/null | awk '{printf "%.1f GB", $1/1073741824}')"

echo
echo "=================== [4] node-exporter 镜像 ==================="
rm -rf /opt/img/rfs-ne
cp -al /opt/img/rfs-base /opt/img/rfs-ne
mkdir -p /opt/img/rfs-ne/usr/local/bin
cp /opt/monitor/node_exporter/node_exporter /opt/img/rfs-ne/usr/local/bin/
tar -C /opt/img/rfs-ne -c . 2>/dev/null | docker import - $REG/node-exporter:local >/dev/null 2>&1
docker run --rm $REG/node-exporter:local /usr/local/bin/node_exporter --version 2>&1 | head -2

echo
echo "=================== [5] 应用层 rootfs（python3 + 依赖）==================="
rm -rf /opt/img/rfs-app
cp -al /opt/img/rfs-base /opt/img/rfs-app
dnf -y --installroot=/opt/img/rfs-app $OPTS install python3 python3-pip > /tmp/b2.log 2>&1
echo "python3 安装退出码 $?"
mkdir -p /opt/img/rfs-app$PYDIR
pip3 install --break-system-packages --target=/opt/img/rfs-app$PYDIR $PYMIRROR \
    flask gunicorn pymysql redis prometheus-client > /tmp/pip1.log 2>&1
echo "pip 退出码 $?"
tail -3 /tmp/pip1.log
ls /opt/img/rfs-app$PYDIR | head -12 | sed 's/^/    /'
tar -C /opt/img/rfs-app -c . 2>/dev/null | docker import - $REG/rhel10-app:local >/dev/null 2>&1
docker run --rm $REG/rhel10-app:local /usr/bin/python3 -c "import flask, gunicorn, pymysql, redis, prometheus_client; print('  [OK] 应用层依赖全部可用')"

echo
echo "=================== [6] 订单服务镜像 ==================="
rm -rf /opt/img/rfs-oa
cp -al /opt/img/rfs-app /opt/img/rfs-oa
mkdir -p /opt/img/rfs-oa/app
cp /opt/order-api/app.py /opt/order-api/init.sql /opt/img/rfs-oa/app/
cp /opt/order-stack/webhook/receiver.py /opt/img/rfs-oa/app/ 2>/dev/null || true
tar -C /opt/img/rfs-oa -c . 2>/dev/null | docker import - $REG/order-api:v1 >/dev/null 2>&1
docker run --rm $REG/order-api:v1 /usr/bin/python3 -c "import sys; sys.path.insert(0,'/app'); import app; print('  [OK] 订单服务代码可导入')"

echo
echo "=================== [7] 告警接收端镜像 ==================="
tar -C /opt/img/rfs-oa -c . 2>/dev/null | docker import - $REG/webhook-receiver:v1 >/dev/null 2>&1
docker run --rm $REG/webhook-receiver:v1 /usr/bin/python3 -c "import sys; sys.path.insert(0,'/app'); import receiver; print('  [OK] 告警接收端可导入')"

echo
echo "=================== [8] 数据库层镜像（mysql + valkey）==================="
rm -rf /opt/img/rfs-db
cp -al /opt/img/rfs-base /opt/img/rfs-db
dnf -y --installroot=/opt/img/rfs-db $OPTS install mysql8.4-server valkey > /tmp/b3.log 2>&1
echo "安装退出码 $?"
# RPM 脚本在 chroot 中未创建 mysql 用户，手工补齐
grep -q '^mysql:' /opt/img/rfs-db/etc/passwd 2>/dev/null || echo 'mysql:x:27:27:MySQL Server:/var/lib/mysql:/sbin/nologin' >> /opt/img/rfs-db/etc/passwd
grep -q '^mysql:' /opt/img/rfs-db/etc/group 2>/dev/null || echo 'mysql:x:27:' >> /opt/img/rfs-db/etc/group
mkdir -p /opt/img/rfs-db/var/lib/mysql /opt/img/rfs-db/var/log/mysql /opt/img/rfs-db/run/mysqld /opt/img/rfs-db/data
chown -R 27:27 /opt/img/rfs-db/var/lib/mysql /opt/img/rfs-db/var/log/mysql /opt/img/rfs-db/run/mysqld 2>/dev/null

cat > /opt/img/rfs-db/usr/local/bin/mysql-entrypoint.sh <<'ENTRY'
#!/bin/bash
set -e
DATADIR=/var/lib/mysql
mkdir -p $DATADIR /run/mysqld
chown -R mysql:mysql $DATADIR /run/mysqld
if [ ! -d "$DATADIR/mysql" ]; then
  echo "[entrypoint] 初始化数据目录 ..."
  mysqld --initialize-insecure --user=mysql --datadir=$DATADIR
fi
echo "[entrypoint] 启动 mysqld ..."
exec mysqld --user=mysql --datadir=$DATADIR \
  --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci \
  --max-connections=300 --slow-query-log=1 --long-query-time=1 \
  --bind-address=0.0.0.0 --port=3306
ENTRY
chmod +x /opt/img/rfs-db/usr/local/bin/mysql-entrypoint.sh
tar -C /opt/img/rfs-db -c . 2>/dev/null | docker import - $REG/rhel10-db:local >/dev/null 2>&1
docker run --rm $REG/rhel10-db:local /bin/bash -c "echo '  [OK] 数据层镜像'; ls /usr/libexec/mysqld /usr/bin/valkey-server; getent passwd mysql"

echo
echo "=================== [9] 本地镜像总览 ==================="
docker images | sed 's/^/  /'
echo "LOCAL-IMAGES-DONE"
