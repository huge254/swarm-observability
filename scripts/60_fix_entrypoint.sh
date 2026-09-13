#!/bin/bash
# 修正 alertmanager / loki 的 command（镜像自带 ENTRYPOINT，不需要再写二进制路径）
set -u
B=/opt/order-stack
STACK=order-observability
cd $B

echo "=================== [1] 修正前 ==================="
grep -n -A4 '^  alertmanager:' docker-compose.yml | head -8 | sed 's/^/  /'
grep -n -A4 '^  loki:' docker-compose.yml | head -8 | sed 's/^/  /'

python3 - <<'PY'
p='/opt/order-stack/docker-compose.yml'
s=open(p).read()

a_old = """      - /bin/alertmanager
      - --config.file=/etc/alertmanager/alertmanager.yml"""
a_new = """      - --config.file=/etc/alertmanager/alertmanager.yml"""
l_old = """      - /usr/bin/loki
      - -config.file=/etc/loki/loki-config.yml"""
l_new = """      - -config.file=/etc/loki/loki-config.yml"""

n = 0
if a_old in s:
    s = s.replace(a_old, a_new); n += 1; print('  alertmanager command 已修正')
else:
    print('  !! alertmanager 未匹配')
if l_old in s:
    s = s.replace(l_old, l_new); n += 1; print('  loki command 已修正')
else:
    print('  !! loki 未匹配')
open(p,'w').write(s)
print('  共修正 %d 处' % n)
PY

echo
echo "=================== [2] 修正后 ==================="
grep -n -A4 '^  alertmanager:' docker-compose.yml | head -8 | sed 's/^/  /'
grep -n -A4 '^  loki:' docker-compose.yml | head -8 | sed 's/^/  /'

echo
echo "=================== [3] 语法校验 ==================="
python3 -c "
import yaml
d=yaml.safe_load(open('/opt/order-stack/docker-compose.yml'))
print('  OK 服务数=%d' % len(d['services']))
print('  alertmanager.command =', d['services']['alertmanager']['command'])
print('  loki.command =', d['services']['loki']['command'])
" 2>&1 | sed 's/^/  /'

echo
echo "=================== [4] 重新部署（增量更新）==================="
docker stack deploy -c docker-compose.yml $STACK 2>&1 | grep -E 'Updating|Creating|error|Error' | sed 's/^/  /'

echo
echo "=================== [5] 等待并查看 ==================="
for i in $(seq 1 10); do
  sleep 10
  echo "  [$(($i*10))s] $(docker stack services $STACK --format '{{.Name}}={{.Replicas}}' 2>/dev/null | tr '\n' ' ')"
  ok=$(docker stack services $STACK --format '{{.Replicas}}' 2>/dev/null | awk -F/ '$1==$2' | wc -l)
  all=$(docker stack services $STACK --format '{{.Name}}' 2>/dev/null | wc -l)
  if [ "$ok" = "$all" ] && [ "$all" != "0" ]; then echo "  >>> 全部服务就绪"; break; fi
done

echo
docker stack services $STACK 2>&1 | sed 's/^/  /'
echo "FIX-ENTRYPOINT-DONE"
