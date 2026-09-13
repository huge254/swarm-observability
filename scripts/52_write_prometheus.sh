#!/bin/bash
# manager：写入 Prometheus 主配置（对接自建容器导出器）+ 12 条告警规则
set -u
B=/opt/order-stack
mkdir -p $B/prometheus/rules

echo "=================== [1] Prometheus 主配置 ==================="
cat > $B/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'order-service-swarm'
    env: 'project4'

rule_files:
  - /etc/prometheus/rules/*.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

scrape_configs:
  # ========== 层级 1：主机层（5 个节点）==========
  - job_name: 'node'
    static_configs:
      - targets: ['192.168.123.20:9100']
        labels: {instance: 'p4-manager', layer: 'host'}
      - targets: ['192.168.123.21:9100']
        labels: {instance: 'p4-worker1', layer: 'host'}
      - targets: ['192.168.123.22:9100']
        labels: {instance: 'p4-worker2', layer: 'host'}
      - targets: ['192.168.123.23:9100']
        labels: {instance: 'p4-worker3', layer: 'host'}
      - targets: ['192.168.123.24:9100']
        labels: {instance: 'p4-worker4', layer: 'host'}

  # ========== 层级 2：容器层（自建容器导出器，替代 cAdvisor）==========
  - job_name: 'container'
    static_configs:
      - targets: ['192.168.123.20:8081']
        labels: {instance: 'p4-manager', layer: 'container'}
      - targets: ['192.168.123.21:8081']
        labels: {instance: 'p4-worker1', layer: 'container'}
      - targets: ['192.168.123.22:8081']
        labels: {instance: 'p4-worker2', layer: 'container'}
      - targets: ['192.168.123.23:8081']
        labels: {instance: 'p4-worker3', layer: 'container'}
      - targets: ['192.168.123.24:8081']
        labels: {instance: 'p4-worker4', layer: 'container'}

  # ========== 层级 3：中间件层 ==========
  - job_name: 'mysql'
    static_configs:
      - targets: ['mysqld-exporter:9104']
        labels: {layer: 'middleware', component: 'mysql'}

  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']
        labels: {layer: 'middleware', component: 'redis'}

  # ========== 层级 4：业务层（Swarm 服务发现）==========
  - job_name: 'order-api'
    metrics_path: /metrics
    dns_sd_configs:
      - names: ['tasks.order-api']
        type: A
        port: 8000

  # ========== 监控自身 ==========
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels: {layer: 'monitor'}
EOF
echo "  采集任务数: $(grep -c 'job_name' $B/prometheus/prometheus.yml)"
echo "  采集目标数: $(grep -c 'targets:' $B/prometheus/prometheus.yml)"

echo
echo "=================== [2] 告警规则（12 条）==================="
cat > $B/prometheus/rules/order-alerts.yml <<'EOF'
groups:
  # ---------------- 主机层（5 条）----------------
  - name: host-layer
    rules:
      - alert: InstanceDown
        expr: up{job=~"node|container|mysql|redis|order-api"} == 0
        for: 1m
        labels: {severity: critical, layer: host}
        annotations:
          summary: "采集目标失联：{{ $labels.instance }} ({{ $labels.job }})"
          description: "Prometheus 连续 1 分钟无法抓取该目标，进程可能已退出或网络中断"

      - alert: HostHighCpuLoad
        expr: (1 - avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[2m]))) * 100 > 85
        for: 3m
        labels: {severity: warning, layer: host}
        annotations:
          summary: "CPU 使用率过高：{{ $labels.instance }}"
          description: "CPU 使用率 {{ printf \"%.1f\" $value }}%，持续超过 85%"

      - alert: HostHighMemory
        expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 90
        for: 3m
        labels: {severity: warning, layer: host}
        annotations:
          summary: "内存使用率过高：{{ $labels.instance }}"
          description: "内存使用率 {{ printf \"%.1f\" $value }}%"

      - alert: HostDiskUsageHigh
        expr: (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay",mountpoint="/"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay",mountpoint="/"}) * 100 > 85
        for: 3m
        labels: {severity: warning, layer: host}
        annotations:
          summary: "磁盘使用率过高：{{ $labels.instance }}"

      - alert: HostDiskWillFillIn4Hours
        expr: predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay",mountpoint="/"}[1h], 4*3600) < 0
        for: 10m
        labels: {severity: warning, layer: host}
        annotations:
          summary: "磁盘将在 4 小时内写满：{{ $labels.instance }}"
          description: "基于近 1 小时写入速率的线性预测，属于趋势告警而非阈值告警"

  # ---------------- 容器层（2 条）----------------
  - name: container-layer
    rules:
      - alert: ContainerHighCpu
        expr: max by(name, service) (container_cpu_usage_percent{name!=""}) > 80
        for: 3m
        labels: {severity: warning, layer: container}
        annotations:
          summary: "容器 CPU 过高：{{ $labels.name }}"
          description: "容器 {{ $labels.service }} 的 CPU 使用率 {{ printf \"%.1f\" $value }}%"

      - alert: ContainerRestartFrequent
        expr: changes(container_status{name!=""}[10m]) > 1
        for: 1m
        labels: {severity: warning, layer: container}
        annotations:
          summary: "容器频繁重启：{{ $labels.name }}"
          description: "10 分钟内容器状态发生多次翻转，疑似反复重启"

  # ---------------- 中间件层（2 条）----------------
  - name: middleware-layer
    rules:
      - alert: MySQLDown
        expr: mysql_up == 0
        for: 1m
        labels: {severity: critical, layer: middleware}
        annotations:
          summary: "MySQL 实例不可用"
          description: "mysqld_exporter 连续 1 分钟无法连接 MySQL，数据库可能已宕机"

      - alert: RedisDown
        expr: redis_up == 0
        for: 1m
        labels: {severity: critical, layer: middleware}
        annotations:
          summary: "Redis(Valkey) 实例不可用"
          description: "redis_exporter 连续 1 分钟无法连接 Valkey"

  # ---------------- 业务层（3 条）----------------
  - name: business-layer
    rules:
      - alert: ApiHighErrorRate
        expr: |
          sum(rate(http_requests_total{job="order-api",code=~"5.."}[5m]))
          /
          sum(rate(http_requests_total{job="order-api"}[5m])) > 0.05
        for: 2m
        labels: {severity: critical, layer: business}
        annotations:
          summary: "订单服务接口错误率超过 5%"
          description: "5xx 占比 {{ printf \"%.2f\" $value }}，持续 2 分钟（for 时长用于抑制瞬时抖动误报）"

      - alert: ApiHighLatencyP95
        expr: |
          histogram_quantile(0.95,
            sum by(le) (rate(http_request_duration_seconds_bucket{job="order-api"}[2m]))
          ) > 0.5
        for: 2m
        labels: {severity: warning, layer: business}
        annotations:
          summary: "订单服务 P95 延迟超过 500ms"
          description: "当前 P95 = {{ printf \"%.0f\" $value }}s"

      - alert: ApiTrafficDrop
        expr: sum(rate(http_requests_total{job="order-api"}[5m])) < 0.1
        for: 3m
        labels: {severity: warning, layer: business}
        annotations:
          summary: "订单服务流量异常下降"
          description: "QPS 低于 0.1，可能上游入口故障或服务已不可达"
EOF
echo "  告警规则条数: $(grep -c 'alert:' $B/prometheus/rules/order-alerts.yml)"
echo "  分组数: $(grep -c '  - name:' $B/prometheus/rules/order-alerts.yml)"
echo "PROMETHEUS-CONFIG-DONE"
