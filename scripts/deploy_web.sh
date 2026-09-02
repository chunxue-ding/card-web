#!/usr/bin/env bash
# card-web 前端一键部署:导出 → 本地预压缩 → rsync → 轻量校验。
# 依赖 /Users/dn/bin/godot 与服务器密钥登录;nginx 侧已开 gzip_static。
set -euo pipefail

GODOT="${GODOT:-/Users/dn/bin/godot}"
SERVER="${SERVER:-root@120.27.241.134}"
REMOTE_DIR="/var/www/card-web"
BASE_URL="${BASE_URL:-http://120.27.241.134}"

cd "$(dirname "$0")/.."
echo "==> 导出 Web 构建"
"$GODOT" --headless --export-release "Web" 2>&1 | grep -iE '\berror\b|failed' && { echo "导出报错"; exit 1; } || true

echo "==> 本地预压缩静态资源(服务器零 CPU)"
for f in index.html index.js index.wasm index.pck index.audio.worklet.js index.audio.position.worklet.js; do
  p="export/web/$f"
  [ -f "$p" ] && gzip -9 -k -f "$p"
done
du -sh export/web | awk '{print "    构建总大小: " $1}'

echo "==> 上传(含 .gz)"
rsync -a --delete --exclude='*.import' export/web/ "$SERVER:$REMOTE_DIR/"

echo "==> 轻量校验(HEAD 大小对比,不下载正文;gz 用 Accept-Encoding 头取 Content-Length)"
fail=0
for f in index.pck index.wasm index.js; do
  local_size=$(stat -f%z "export/web/$f")
  remote_size=$(curl -sI --max-time 10 "$BASE_URL/$f" | awk 'tolower($1)=="content-length:"{gsub("\r","");print $2}')
  gz_size=$(stat -f%z "export/web/$f.gz")
  remote_gz=$(curl -sI --max-time 10 -H 'Accept-Encoding: gzip' "$BASE_URL/$f" | awk 'tolower($1)=="content-length:"{gsub("\r","");print $2}')
  if [ "$local_size" = "$remote_size" ] && [ "$gz_size" = "$remote_gz" ]; then
    echo "    ✓ $f  原始 ${local_size}B / gz ${gz_size}B"
  else
    echo "    ✗ $f  本地 ${local_size}/${gz_size} vs 线上 ${remote_size}/${remote_gz}"; fail=1
  fi
done
[ "$fail" = 0 ] || { echo "校验不一致"; exit 1; }

echo "==> 服务健康"
curl -s --max-time 8 "$BASE_URL/api/v1/healthz"; echo
curl -s -o /dev/null -w "页面 %{http_code}\n" --max-time 8 "$BASE_URL/"
echo "部署完成 ✓"
