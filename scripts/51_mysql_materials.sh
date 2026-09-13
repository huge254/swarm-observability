#!/bin/bash
# manager：写入项目4 部署物料（MySQL 启动脚本 / 初始化 SQL）
set -u
B=/opt/order-stack
mkdir -p $B/mysql $B/prometheus/rules $B/alertmanager $B/loki $B/grafana/provisioning/datasources

echo "=================== [1] MySQL 启动脚本 ==================="
cat > $B/mysql/entrypoint.sh <<'SH'
#!/bin/bash
# MySQL 8.4 单实例启动脚本：首次启动自动初始化数据目录并导入 schema
set -e
DATADIR=/var/lib/mysql
SOCK=/var/run/mysqld/mysqld.sock
LOG=/var/log/mysql/error.log

mkdir -p "$DATADIR" /var/run/mysqld /var/log/mysql
chown -R mysql:mysql "$DATADIR" /var/run/mysqld /var/log/mysql

if [ ! -d "$DATADIR/mysql" ]; then
  echo "[entrypoint] 首次启动，初始化数据目录 ..."
  mysqld --initialize-insecure --user=mysql --datadir="$DATADIR"
  echo "[entrypoint] 数据目录初始化完成"
fi

echo "[entrypoint] 启动 mysqld（加载 /etc/mysql-init/init.sql）..."
exec mysqld \
  --user=mysql \
  --datadir="$DATADIR" \
  --socket="$SOCK" \
  --pid-file=/var/run/mysqld/mysqld.pid \
  --bind-address=0.0.0.0 \
  --port=3306 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci \
  --max-connections=300 \
  --slow-query-log=1 \
  --long-query-time=1 \
  --log-error="$LOG" \
  --init-file=/etc/mysql-init/init.sql
SH
chmod +x $B/mysql/entrypoint.sh
echo "  已写入 entrypoint.sh（$(wc -l < $B/mysql/entrypoint.sh) 行）"

echo
echo "=================== [2] 初始化 SQL ==================="
cat > $B/mysql/init.sql <<'SQL'
-- 跨境电商订单服务：库 / 业务账号 / 导出账号 / 表结构 / 种子数据
CREATE DATABASE IF NOT EXISTS shop DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'orderapp'@'%' IDENTIFIED BY 'Order@1234';
ALTER USER 'orderapp'@'%' IDENTIFIED BY 'Order@1234';
GRANT ALL PRIVILEGES ON shop.* TO 'orderapp'@'%';

CREATE USER IF NOT EXISTS 'exporter'@'%' IDENTIFIED BY 'Exporter@1234';
ALTER USER 'exporter'@'%' IDENTIFIED BY 'Exporter@1234';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';

FLUSH PRIVILEGES;

USE shop;

CREATE TABLE IF NOT EXISTS products (
  sku        VARCHAR(32) PRIMARY KEY,
  name       VARCHAR(64) NOT NULL,
  price      DECIMAL(10,2) NOT NULL,
  stock      INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS orders (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  sku        VARCHAR(32) NOT NULL,
  qty        INT NOT NULL,
  status     VARCHAR(16) NOT NULL DEFAULT 'CREATED',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_sku (sku),
  INDEX idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO products (sku,name,price,stock) VALUES
 ('SKU-1001','无线蓝牙耳机',299.00,500),
 ('SKU-1002','智能手环',199.00,300),
 ('SKU-1003','便携充电宝',129.00,800),
 ('SKU-1004','机械键盘',459.00,150),
 ('SKU-1005','4K 显示器',1299.00,60);
SQL
echo "  已写入 init.sql（$(wc -l < $B/mysql/init.sql) 行）"

echo
ls -l $B/mysql | sed 's/^/  /'
echo "MYSQL-MATERIALS-DONE"
