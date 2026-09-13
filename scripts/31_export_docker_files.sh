#!/bin/bash
# 在已装 Docker 的节点上打包全部安装文件，供 worker2 离线复刻
set -u
echo "===== $(hostname) 导出 Docker 安装文件 ====="

LIST=/tmp/docker_files.txt
rpm -ql docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null | grep -v '^/etc/docker/daemon.json$' > $LIST
echo "  文件条目数: $(wc -l < $LIST)"
echo "  其中目录: $(while read f; do [ -d "$f" ] && echo x; done < $LIST | wc -l)"

cd /
tar -czf /tmp/docker_pkg.tar.gz -T $LIST --ignore-failed-read 2>/dev/null
echo "  打包结果:"
ls -lh /tmp/docker_pkg.tar.gz | sed 's/^/    /'
echo "  tar 内条目: $(tar -tzf /tmp/docker_pkg.tar.gz 2>/dev/null | wc -l)"

echo
echo "  docker 组: $(getent group docker || echo '(无 docker 组)')"
echo "  RPM 版本清单:"
rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null | sed 's/^/    /'
echo "EXPORT-DONE"
