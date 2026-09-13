#!/bin/bash
# manager：写入项目4 Swarm 编排文件（全部使用私有仓库自建镜像）
set -u
B=/opt/order-stack
mkdir -p $B

echo "=================== [1] 写入 docker-compose.yml ==================="
cat > $B/docker-compose.yml <<'EOF'
version: "3.8"

# ============================================================
# 跨境电商订单服务 —— 云原生可观测性平台
# 所有镜像均来自本集群私有仓库（离线环境自建，零外网依赖）
# ============================================================

networks:
  order-net:
    driver: overlay
    attachable: true

volumes:
  mysql-data:
  redis-data:
  prometheus-data:
  alertmanager-data:
  grafana-data:
  loki-data:

configs:
  prometheus_yml:
    file: ./prometheus/prometheus.yml
  order_alerts:
    file: ./prometheus/rules/order-alerts.yml
  alertmanager_yml:
    file: ./alertmanager/alertmanager.yml
  mysql_entry:
    file: ./mysql/entrypoint.sh
  mysql_init:
    file: ./mysql/init.sql
  loki_yml:
    file: ./loki/loki-config.yml
  grafana_ds:
    file: ./grafana/provisioning/datasources/datasources.yml

services:

  # ==================== 数据层 ====================
  mysql:
    image: 192.168.123.20:5000/rhel10-db:local
    command: ["/bin/bash", "/etc/mysql-init/entrypoint.sh"]
    configs:
      - source: mysql_entry
        target: /etc/mysql-init/entrypoint.sh
        mode: 0755
      - source: mysql_init
        target: /etc/mysql-init/init.sql
        mode: 0644
    volumes:
      - mysql-data:/var/lib/mysql
    networks: [order-net]
    deploy:
      replicas: 1
      placement:
        constraints: [node.hostname == p4-worker2]
      restart_policy:
        condition: on-failure
        delay: 5s
      resources:
        limits: {memory: 640M}

  redis:
    image: 192.168.123.20:5000/rhel10-db:local
    command:
      - /usr/bin/valkey-server
      - --bind
      - 0.0.0.0
      - --port
      - "6379"
      - --appendonly
      - "yes"
      - --dir
      - /data
      - --maxmemory
      - 128mb
      - --maxmemory-policy
      - allkeys-lru
    volumes:
      - redis-data:/data
    networks: [order-net]
    deploy:
      replicas: 1
      placement:
        constraints: [node.hostname == p4-worker3]
      restart_policy:
        condition: on-failure
        delay: 5s
      resources:
        limits: {memory: 192M}

  # ==================== 业务层 ====================
  order-api:
    image: 192.168.123.20:5000/order-api:v3
    environment:
      DB_HOST: mysql
      DB_PORT: "3306"
      DB_USER: orderapp
      DB_PASSWORD: "Order@1234"
      DB_NAME: shop
      REDIS_HOST: redis
      REDIS_PORT: "6379"
      APP_VERSION: "v1"
    ports:
      - target: 8000
        published: 8000
        mode: ingress
    networks: [order-net]
    deploy:
      replicas: 2
      update_config:
        parallelism: 1
        delay: 10s
        order: start-first
      restart_policy:
        condition: on-failure
        delay: 5s
      resources:
        limits: {memory: 256M}

  webhook-receiver:
    image: 192.168.123.20:5000/webhook-receiver:v2
    environment:
      REDIS_HOST: redis
      REDIS_PORT: "6379"
    ports:
      - target: 8080
        published: 8080
        mode: ingress
    networks: [order-net]
    deploy:
      replicas: 1
      placement:
        constraints: [node.hostname == p4-worker3]
      restart_policy:
        condition: on-failure
        delay: 5s
      resources:
        limits: {memory: 160M}

  # ==================== 采集层（全局部署）====================
  node-exporter:
    image: 192.168.123.20:5000/node-exporter:local
    command:
      - /usr/local/bin/node_exporter
      - --path.procfs=/host/proc
      - --path.sysfs=/host/sys
      - --path.rootfs=/host/root
      - --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc|var/lib/docker/.+)($$|/)
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/host/root:ro,rslave
    ports:
      - target: 9100
        published: 9100
        mode: host
    networks: [order-net]
    deploy:
      mode: global
      resources:
        limits: {memory: 128M}

  container-exporter:
    image: 192.168.123.20:5000/container-exporter:v1
    command: ["/usr/bin/python3", "/app/exporter.py"]
    environment:
      EXPORTER_PORT: "8081"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    ports:
      - target: 8081
        published: 8081
        mode: host
    networks: [order-net]
    deploy:
      mode: global
      resources:
        limits: {memory: 160M}

  # ==================== 中间件导出层 ====================
  mysqld-exporter:
    image: 192.168.123.20:5000/mysqld-exporter:local
    command:
      - --mysqld.address=mysql:3306
      - --mysqld.username=exporter
    environment:
      MYSQLD_EXPORTER_PASSWORD: "Exporter@1234"
    networks: [order-net]
    deploy:
      replicas: 1
      placement:
        constraints: [node.hostname == p4-worker2]
      restart_policy:
        condition: on-failure
        delay: 5s
      resources:
        limits: {memory: 128M}

  redis-exporter:
    image: 192.168.123.20:5000/redis-exporter:v1.62.0
    environment:
      REDIS_ADDR: "redis://redis:6379"
    networks: [order-net]
    deploy:
      replicas: 1
      placement:
        constraints: [node.hostname == p4-worker3]
      restart_policy:
        condition: on-failure
        delay: 5s
      resources:
        limits: {memory: 128M}

  # ==================== 监控存储与告警 ====================
  prometheus:
    image: 192.168.123.20:5000/prometheus:local
    command:
      - /usr/local/bin/prometheus
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --storage.tsdb.retention.time=15d
      - --web.enable-lifecycle
      - --web.enable-admin-api
    configs:
      - source: prometheus_yml
        target: /etc/prometheus/prometheus.yml
        mode: 0444
      - source: order_alerts
        target: /etc/prometheus/rules/order-alerts.yml
        mode: 0444
    volumes:
      - prometheus-data:/prometheus
    ports:
      - target: 9090
        published: 9090
        mode: ingress
    networks: [order-net]
    deploy:
      replicas: 1
      placement:
        constraints: [node.hostname == p4-manager]
      restart_policy:
        condition: on-failure
        delay: 5s
      resources:
        limits: {memory: 448M}

  alertmanager:
    image: 192.168.123.20:5000/alertmanager:local
    command:
      - /bin/alertmanager
      - --config.file=/etc/alertmanager/alertmanager.yml
      - --storage.path=/alertmanager
    configs:
      - source: alertmanager_yml
        target: /etc/alertmanager/alertmanager.yml
        mode: 0444
    volumes:
      - alertmanager-data:/alertmanager
    ports:
      - target: 9093
        published: 9093
        mode: ingress
    networks: [order-net]
    deploy:
      replicas: 1
      placement:
        constraints: [node.hostname == p4-manager]
      restart_policy:
        condition: on-failure
        delay: 5s
      resources:
        limits: {memory: 192M}

  grafana:
    image: 192.168.123.20:5000/grafana:local
    command:
      - /usr/share/grafana/bin/grafana
      - server
      - --homepath
      - /usr/share/grafana
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: admin123
      GF_USERS_ALLOW_SIGN_UP: "false"
    configs:
      - source: grafana_ds
        target: /etc/grafana/provisioning/datasources/datasources.yml
        mode: 0444
    volumes:
      - grafana-data:/var/lib/grafana
    ports:
      - target: 3000
        published: 3000
        mode: ingress
    networks: [order-net]
    deploy:
      replicas: 1
      placement:
        constraints: [node.hostname == p4-manager]
      restart_policy:
        condition: on-failure
        delay: 5s
      resources:
        limits: {memory: 384M}

  # ==================== 日志 ====================
  loki:
    image: 192.168.123.20:5000/loki:local
    command:
      - /usr/bin/loki
      - -config.file=/etc/loki/loki-config.yml
    configs:
      - source: loki_yml
        target: /etc/loki/loki-config.yml
        mode: 0444
    volumes:
      - loki-data:/loki
    ports:
      - target: 3100
        published: 3100
        mode: ingress
    networks: [order-net]
    deploy:
      replicas: 1
      placement:
        constraints: [node.hostname == p4-worker4]
      restart_policy:
        condition: on-failure
        delay: 5s
      resources:
        limits: {memory: 384M}
EOF

echo "  已写入 docker-compose.yml（$(wc -l < $B/docker-compose.yml) 行）"

echo
echo "=================== [2] YAML 语法校验 ==================="
python3 - <<'PY'
import yaml
p='/opt/order-stack/docker-compose.yml'
try:
    d=yaml.safe_load(open(p))
    print('  OK   docker-compose.yml')
    print('  服务数: %d' % len(d['services']))
    print('  配置数: %d' % len(d['configs']))
    for s in sorted(d['services']):
        print('    - %s' % s)
except Exception as e:
    print('  FAIL -> %s' % e)
PY

echo
echo "=================== [3] 配置引用的文件是否存在 ==================="
for f in prometheus/prometheus.yml prometheus/rules/order-alerts.yml alertmanager/alertmanager.yml mysql/entrypoint.sh mysql/init.sql loki/loki-config.yml grafana/provisioning/datasources/datasources.yml; do
  if [ -f "$B/$f" ]; then echo "  OK      $f"; else echo "  MISSING $f"; fi
done
echo "STACK-FILE-DONE"
