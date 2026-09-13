#!/bin/bash
# 离线镜像方案第一步：用 RHEL 10 DVD 构建 Docker 基础镜像
set -u

echo "=================== [1] GitHub 可达性（决定能否拿到 alertmanager/loki）==================="
for u in https://github.com/ https://objects.githubusercontent.com/ https://api.github.com/ ; do
  code=$(timeout 8 curl -sI -o /dev/null -w '%{http_code}' "$u" 2>/dev/null)
  printf '  %-46s -> %s\n' "$u" "${code:-fail}"
done

echo
echo "=================== [2] 光驱与仓库检查 ==================="
findmnt /mnt >/dev/null 2>&1 || mount /dev/sr0 /mnt 2>/dev/null
findmnt /mnt | tail -1
ls /mnt | head -4
dnf repolist 2>/dev/null | tail -4

echo
echo "=================== [3] 构建最小 rootfs（dnf --installroot）==================="
ROOTFS=/opt/img/rootfs
rm -rf $ROOTFS
mkdir -p $ROOTFS
dnf -y --installroot=$ROOTFS --releasever=10 --nogpgcheck \
    --setopt=reposdir=/etc/yum.repos.d \
    --setopt=install_weak_deps=False \
    --setopt=tsflags=nodocs \
    install bash coreutils glibc-common shadow-utils tzdata procps-ng \
    > /tmp/base_build.log 2>&1
echo "dnf 退出码: $?"
echo "--- 日志尾部 ---"
tail -6 /tmp/base_build.log
echo "--- rootfs 大小 ---"
du -sh $ROOTFS 2>/dev/null
ls $ROOTFS

echo
echo "=================== [4] 导入为 Docker 镜像 ==================="
tar -C $ROOTFS -c . 2>/dev/null | docker import - rhel10-base:10.2 2>&1 | tail -2
docker images | head -6

echo
echo "=================== [5] 验证基础镜像 ==================="
docker run --rm rhel10-base:10.2 /bin/bash -c "echo BASE-IMAGE-OK; cat /etc/redhat-release 2>/dev/null || echo '(no release file)'; bash --version | head -1; command -v dnf || echo 'dnf 未包含（正常，容器内不需要）'"
echo "BASE-IMAGE-DONE"
