#!/bin/bash
# V计划学生信息认证 - macOS .app 打包脚本
# 用法: ./build_app.sh
# 输出: ./V计划学生信息认证.app

set -e

# 切换到脚本所在目录
cd "$(dirname "$0")"

APP_NAME="V计划学生信息认证"
BIN_NAME="V计划学生信息认证"
BUNDLE_ID="com.vplan.studentauth"
ICON_PNG="icon.png"
ICONSET_DIR="/tmp/V计划.iconset"
ICNS_FILE="icon.icns"

# 1. 检查图标
if [ ! -f "$ICON_PNG" ]; then
  echo "❌ 缺少 $ICON_PNG"
  exit 1
fi

# 2. 准备二进制 (按优先级: 当前目录 -> 旧 .app -> 重新编译)
if [ ! -f "$BIN_NAME" ]; then
  OLD_BIN="${APP_NAME}.app/Contents/MacOS/${BIN_NAME}"
  if [ -f "$OLD_BIN" ]; then
    echo "📋 从旧 .app 复制二进制..."
    cp "$OLD_BIN" "$BIN_NAME"
    chmod +x "$BIN_NAME"
  else
    if ! command -v go &>/dev/null; then
      echo "❌ 找不到 $BIN_NAME，也未安装 Go"
      exit 1
    fi
    echo "🔨 编译 Go 二进制..."
    go build -o "$BIN_NAME" main.go
  fi
fi

# 3. 生成 icon.iconset (macOS 要求的多种尺寸)
echo "📐 生成 iconset..."
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# sips 是 macOS 自带的图片处理工具
sips -z 16 16     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png"        >/dev/null
sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png"     >/dev/null
sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png"        >/dev/null
sips -z 64 64     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png"     >/dev/null
sips -z 128 128   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png"      >/dev/null
sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png"   >/dev/null
sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png"      >/dev/null
sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png"   >/dev/null
sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png"      >/dev/null
sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png"   >/dev/null

# 4. 把 iconset 转为 icns
echo "🎨 生成 icon.icns..."
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"
rm -rf "$ICONSET_DIR"

# 5. 构建 .app bundle 结构
APP_DIR="${APP_NAME}.app"
echo "📦 打包 $APP_DIR ..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# 复制可执行文件
cp "$BIN_NAME" "$APP_DIR/Contents/MacOS/$BIN_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$BIN_NAME"

# 复制图标
cp "$ICNS_FILE" "$APP_DIR/Contents/Resources/$ICNS_FILE"

# 6. 生成 Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${BIN_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>icon</string>
  <key>CFBundleIconName</key>
  <string>icon</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>10.13</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.education</string>
</dict>
</plist>
PLIST

# 7. 清理残留的 .DS_Store 和 _ 前缀的 macOS 资源文件
find "$APP_DIR" -name "._*" -delete 2>/dev/null || true
find "$APP_DIR" -name ".DS_Store" -delete 2>/dev/null || true

# 8. 校验 Info.plist
echo "🔍 校验 Info.plist..."
plutil -lint "$APP_DIR/Contents/Info.plist"

# 9. 触发 Launch Services 重新读取图标
touch "$APP_DIR"
lsregister -f "$APP_DIR" 2>/dev/null || true

echo "✅ 打包完成: $(pwd)/$APP_DIR"
echo "   - 可执行: $APP_DIR/Contents/MacOS/$BIN_NAME"
echo "   - 图标:   $APP_DIR/Contents/Resources/$ICNS_FILE"
echo "   - 双击即可在 Finder 中显示图标"
