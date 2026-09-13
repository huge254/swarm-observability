# 跨境电商订单服务 —— 云原生监控告警体系（Docker Swarm + Prometheus）

一个**在完全离线的环境下从零构建**的 5 节点 Docker Swarm 集群：订单业务服务 + MySQL + Redis + Prometheus / Grafana / Alertmanager / Loki 可观测栈 + 四层 12 条告警规则 + **告警闭环时延实测**。

> 平台：VMware Workstation 17.6.4 ｜ 系统：Red Hat Enterprise Linux 10.2（内核 6.12）
> 规格：5 台 × 4 vCPU / 1.6 GB / 44 GB ｜ 编排：Docker Swarm（1 manager + 4 worker）
> 所有数字均为真实演练采集，配置与脚本均来自真实运行环境

---

## 一、核心结果

| 指标 | 实测值 |
|:--|:--|
| **Swarm 服务副本** | **12 个服务全部达成期望副本** |
| **Prometheus 采集目标** | **15 / 15 全部 up** |
| **告警规则** | **12 条**（主机 5 / 容器 2 / 中间件 2 / 业务 3） |
| **自建镜像** | **13 个**（零外网依赖） |
| 业务链路 | 下单 201、库存 500→498→496、查询/列表/指标正常 |
| **告警端到端时延（MySQL 宕机）** | **86 秒** ＝ 检测 83s + **通知 3s** |
| 告警端到端时延（错误率飙升） | **159 秒** ＝ 检测 155s + 通知 4s |
| 告警端到端时延（Redis 宕机） | **≈93 秒** |

**最有价值的一条结论**：86 秒里真正属于"通知链路"的只有 **3 秒**，剩下 83 秒全是采集间隔 + 规则评估 + `for` 抑制时长。
**觉得告警慢，要优化的不是 Alertmanager，而是 `for` 的配置和采集周期。**

---

## 二、架构

```
                    ┌──────────────────────────────────────────┐
                    │           p4-manager (.20)               │
                    │  Swarm Manager │ 私有 Registry :5000      │
                    │  Prometheus    │ Grafana     │ Alertmanager│
                    │  node-exporter │ 容器指标导出器            │
                    └──────────────────────────────────────────┘
                                       │  overlay 网络 order-net
        ┌──────────────┬───────────────┼───────────────┬──────────────┐
        ▼              ▼               ▼               ▼              ▼
   p4-worker1(.21) p4-worker2(.22) p4-worker3(.23) p4-worker4(.24)
   order-api 副本   MySQL 8.4        Valkey 8.0       Loki 2.9
                    mysqld-exporter  order-api 副本
                                     webhook-receiver
                                     redis-exporter
   └── 四台均跑：node-exporter(global) + 容器指标导出器(global) ──┘

   监控链路：业务/中间件/容器/主机 → Prometheus → 12 条规则 → Alertmanager
                                                        ↓ webhook
                                                   告警接收端（记录到达时刻）
```

### 服务清单（12 个 Swarm 服务）

| 服务 | 副本 | 镜像 | 说明 |
|:--|:--|:--|:--|
| order-api | 2/2 | order-api:v4 | Flask + Gunicorn 订单服务 |
| mysql | 1/1 | rhel10-db:local | MySQL 8.4.8（config 注入启动脚本 + init.sql） |
| redis | 1/1 | rhel10-db:local | Valkey 8.0.7（AOF + LRU 淘汰） |
| webhook-receiver | 1/1 | webhook-receiver:v4 | 告警接收端，记录 `receive_ts` |
| prometheus | 1/1 | prometheus:local | Prometheus 3.5.3 |
| grafana | 1/1 | grafana:local | Grafana 13.0.2 |
| alertmanager | 1/1 | alertmanager:local | Alertmanager 0.27.0 |
| loki | 1/1 | loki:local | Loki 2.9.0 |
| node-exporter | 5/5 | node-exporter:local | 主机层指标，global + host 模式端口 |
| container-exporter | 5/5 | container-exporter:v1 | **自研**容器指标导出器，替代 cAdvisor |
| mysqld-exporter | 1/1 | mysqld-exporter:local | MySQL 中间件指标 |
| redis-exporter | 1/1 | redis-exporter:v1.62.0 | Redis 中间件指标 |

---

## 三、目录结构

```
.
├── README.md
├── deploy/
│   ├── docker-compose.yml            # Swarm 栈定义（12 服务 / 7 config）
│   ├── prometheus/
│   │   ├── prometheus.yml            # 四层 15 个采集目标
│   │   └── rules/order-alerts.yml    # 12 条告警规则
│   ├── alertmanager/alertmanager.yml # 分级路由 + 2 条抑制规则
│   ├── mysql/                        # entrypoint.sh + init.sql
│   ├── loki/loki-config.yml
│   └── grafana/datasources.yml
├── app/
│   ├── container_exporter.py         # 自研容器指标导出器（纯标准库）
│   ├── webhook_receiver.py           # 告警接收端（内存兜底 + 读路径熔断）
│   └── loadgen.py                    # 负载发生器（纯标准库）
└── scripts/
    ├── 01_base.sh … 93_rename_hosts.sh   # 按执行顺序编号的部署脚本
    ├── drill-alert-latency.sh            # 告警闭环演练脚本
    └── measurement/                      # 数据采集脚本
```

---

## 四、快速验证

```bash
# 集群与服务
docker node ls
docker stack services order-observability
docker stack ps order-observability

# 采集目标（应 15/15 up）
curl -s http://192.168.123.20:9090/api/v1/targets | jq '[.data.activeTargets[].health] | group_by(.) | map({(.[0]): length})'

# 告警规则（应 12 条）
curl -s http://192.168.123.20:9090/api/v1/rules | jq '[.data.groups[].rules[]] | length'

# 业务链路
curl -X POST http://192.168.123.20:8000/api/orders -H 'Content-Type: application/json' -d '{"sku":"SKU-1001","qty":2}'
curl http://192.168.123.20:8000/api/orders/1
```

**访问入口**：

| 组件 | 地址 | 账号 |
|:--|:--|:--|
| Grafana | http://192.168.123.20:3000 | admin / admin123 |
| Prometheus | http://192.168.123.20:9090 | — |
| Alertmanager | http://192.168.123.20:9093 | — |
| 订单服务 | http://192.168.123.20:8000/health | — |
| 告警接收端 | http://192.168.123.20:8080/alerts | — |

**压测与故障演练**：

```bash
# 打流量
python3 app/loadgen.py --url http://127.0.0.1:8000 --concurrency 20 --duration 60

# 制造 5xx：错误率告警演练
python3 app/loadgen.py --url http://127.0.0.1:8000 --concurrency 15 --duration 300 --mode error

# 告警闭环时延演练（自动注入故障 + 计时 + 恢复）
bash scripts/drill-alert-latency.sh
```

---

## 五、技术亮点

### 1. 离线环境零外网依赖：13 个镜像全部自建

公网镜像站实测情况：Docker Hub 与 `objects.githubusercontent.com` **完全不可达**，
`docker.xuanyuan.me` DNS 超时，`docker.1panel.live` 时通时断，**拉取速度约 80 kB/s**（拉 1.7 GB 需 6 小时）。

因此整栈自建：

```
rhel10-base:local   (bash/coreutils/glibc/shadow-utils/tzdata)
   ├── rhel10-app:local  (+python3.12 +pip3)
   │      ├── order-api:v4         (+flask/gunicorn/pymysql/redis/prometheus-client/cryptography)
   │      └── webhook-receiver:v4  (+flask/redis/gunicorn)
   └── rhel10-db:local   (+mysql8.4-server +valkey)
```

监控组件为「rootfs + 静态二进制」自建：prometheus / grafana / node-exporter。
最终 **私有 Registry 中 13 个仓库名**，全栈零外网依赖分发。

### 2. 四层告警体系 + 12 条规则

| 层 | 采集者 | 规则数 | 规则 |
|:--|:--|:--|:--|
| 主机层 | node-exporter | 5 | InstanceDown、HostHighCpuLoad、HostHighMemory、HostDiskUsageHigh、HostDiskWillFillIn4Hours |
| 容器层 | 自研容器导出器 | 2 | ContainerHighCpu、ContainerRestartFrequent |
| 中间件层 | mysqld/redis-exporter | 2 | MySQLDown、RedisDown |
| 业务层 | 应用埋点 | 3 | ApiHighErrorRate、ApiHighLatencyP95、ApiTrafficDrop |

设计原则：**每层都有 critical（关键故障不漏）+ 趋势项（在变成故障前发现）**，
对应 Google SRE 四个黄金信号的分层落地。

### 3. 告警闭环时延可量化

在集群内部署**告警接收端**，Alertmanager 推送的每条告警都记录 `receive_ts`，
使"故障注入 → 告警触达"成为**可测量的端到端指标**，并能拆解为「检测段」和「通知段」：

```
故障注入 ──┬─ 采集间隔 (15s) ──┐
           ├─ 规则评估 (15s)   ├──→ Prometheus 进入 firing  → +83s
           └─ for 抑制 (60s)   ─┘
                                    ↓ Alertmanager
           └─ 路由 group_wait (critical 5s) ──→ 告警接收端  → +86s
                                    └── 通知段仅 3 秒 ──┘
```

### 4. 自研组件替代不可获取的开源件

| 缺失组件 | 替代方案 | 说明 |
|:--|:--|:--|
| cAdvisor | **自研容器指标导出器** | 调 Docker API `/containers/{id}/stats`，用 `cpu_stats`/`precpu_stats` 差分算 CPU；**指标命名与 cAdvisor 兼容，原告警规则无需改动**；纯标准库实现，零 PyPI 依赖 |
| Promtail | 未做 | Loki 已就绪，但**日志采集链路未打通**，本仓库不包含日志采集部分 |

### 5. 真实排障（7 条，全部保留原始报错）

| # | 问题 | 根因 | 修复 |
|:-:|:--|:--|:--|
| 1 | `docker swarm init` 反复失败 | `live-restore` 与 Swarm 模式不兼容 | 从 daemon.json 移除 |
| 2 | worker2 装不上 Docker | 镜像站 RPM 下载超时，且失败事务会清空 dnf 缓存 | **从已装节点按 `rpm -ql` 打包复刻** + `restorecon` |
| 3 | 栈部署中断 | Compose 对 `$` 做插值，正则需写成 `$$` | `($\|/)` → `($$\|/)` |
| 4 | alertmanager / loki 反复 exit 1 | 官方镜像**自带 ENTRYPOINT**，command 又传了一遍二进制 | 只保留参数 |
| 5 | RedisDown 误报 | Valkey **protected-mode** 未设密码时只接受回环连接 | 启动参数加 `--protected-mode no` |
| 6 | 接口 500 | Flask 3.x **不允许 `jsonify(obj, key=value)` 混用**位置与关键字参数 | `jsonify(dict(row, source='mysql'))` |
| 7 | 告警记录整体不可见 | 接收端**读路径同步依赖 Redis**，Redis 挂时 DNS 解析阻塞致接口超时 | 内存兜底 + 1s 超时 + **30s 熔断** |

> **第 7 条是本项目最有价值的设计经验**：*监控 / 告警链路自身的读路径，绝对不能与被监控组件强耦合* ——
> 最需要告警的时刻，恰恰是被监控组件已经挂了的时候。

---


---

## 六、已知缺口与改进方向

主动列出边界，而不是回避：

| 缺口 | 说明 | 改进方向 |
|:--|:--|:--|
| **Prometheus 单点** | 它挂了就没人告警，且**无法报告自己的死亡** | 异地心跳（Watchdog 模式），外部服务超出被监控体系 |
| **单 manager** | manager 挂掉后无法调度新任务（已运行服务不受影响） | manager 扩到 3 或 5 个（奇数） |
| **MySQL 单实例 + 固定节点约束** | `node.hostname == p4-worker2`，该节点整机故障则无法调度 | 数据卷改用 NFS/云盘驱动，或上 MySQL 主从 + 自动切换 |
| **日志链路未打通** | Loki 就绪但无 Promtail | 自研轻量采集器读容器 json-log 推送 Loki |
| **敏感配置用 config 而非 secret** | compose 中 MySQL 密码为明文 | 改用 `docker secret`（加密存储 + tmpfs 挂载） |
| **镜像由手工 commit 生成** | 不可复现 | 改为 CI 从源码构建，语义化 tag |
| **D4 延迟告警演练未完成** | P95 劣化场景脚本中断 | 补齐并回填数据 |
| 网络是扁平 NAT | 未验证跨网段/跨机房场景 | 引入多网段或 VLAN 划分 |
