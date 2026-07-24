#!/usr/bin/env bash
# 同步部署目录：将源码与 vendor 复制到 public/，避免线上与源码漂移。
# 用法：bash scripts/sync-public.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p public/src
cp src/config.js   public/src/config.js
cp index.html      public/index.html
cp query.html      public/query.html
cp admin.html      public/admin.html
cp _headers        public/_headers
rm -rf public/vendor          # 先清理，避免 cp -R 在已存在时产生 public/vendor/vendor 嵌套重复
cp -R vendor       public/vendor

echo "✓ public/ 已同步："
echo "  - index.html / query.html / admin.html"
echo "  - src/config.js"
echo "  - vendor/ ($(find vendor -type f | wc -l | tr -d ' ') 个文件)"
echo "提示：public/ 仅用于部署，请勿直接编辑，改动请先改根目录源码再运行本脚本。"
