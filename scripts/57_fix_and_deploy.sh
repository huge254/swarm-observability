#!/bin/bash
# 修正 compose 中未转义的 $（node-exporter 的排除正则），然后部署
set -u
B=/opt/order-stack
STACK=order-observability
cd $B

echo "=================== [1] 修正转义 ==================="
python3 - <<'PY'
p='/opt/order-stack/docker-compose.yml'
s=open(p).read()
old='var/lib/docker/.+)($|/)'
new='var/lib/docker/.+)($$|/)'
if old in s:
    open(p,'w').write(s.replace(old,new))
    print('  已替换 -> ($$|/)')
elif new in s:
    print('  已是转义状态')
else:
    print('  !! 未找到目标字符串')
PY
grep -n 'mount-points-exclude' $B/docker-compose.yml | sed 's/^/  /'

echo
echo "=================== [2] 再次校验语法 ==================="
python3 -c "
import yaml
d=yaml.safe_load(open('/opt/order-stack/docker-compose.yml'))
print('  OK 服务数=%d 配置数=%d' % (len(d['services']), len(d['configs'])))
" 2>&1 | sed 's/^/  /'

echo
echo "=================== [3] 部署 ==================="
docker stack deploy -c docker-compose.yml $STACK 2>&1 | head -30 | sed 's/^/  /'

echo
echo "=================== [4] 立即查看服务 ==================="
sleep 5
docker stack services $STACK 2>&1 | sed 's/^/  /'
echo "FIX-DEPLOY-DONE"
