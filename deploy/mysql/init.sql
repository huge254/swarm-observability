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
