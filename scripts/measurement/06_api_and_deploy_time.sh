#!/bin/bash
# 采集项：项目1、7、9 —— 接口响应时间、容器数量、部署耗时
# 用法：bash 06_api_and_deploy_time.sh [接口URL]
set -u
URL="${1:-http://127.0.0.1:8000/api/students?page=1}"

echo "== 1) 容器数量与状态 =="
echo "  容器总数: $(docker ps -q | wc -l)"
docker ps --format '  {{.Names}}  {{.Status}}' 2>/dev/null

echo
echo "== 2) 接口响应时间（10 次）=="
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "  run $i: total=%{time_total}s  http=%{http_code}\n" --max-time 5 "$URL"
done
echo "  取中位数写入简历；若含数据库查询，注明「含一次分页查询」更可信"

echo
echo "== 3) 部署耗时（手动对比）=="
echo "  手工部署：按你原来的步骤重新走一遍，用 time 记录"
echo "    time bash deploy_manual.sh"
echo "  容器部署："
echo "    time docker compose up -d --build"
echo "  两个时间之差 = 简历里的「部署耗时由 X 分钟降至 Y 分钟」"

echo
echo "== 4) 容器化迁移耗时（项目10 用）=="
echo "  在干净机器上 time docker compose up -d，记录首次可用时间"
