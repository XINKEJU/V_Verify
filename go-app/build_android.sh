#!/bin/bash
# V计划学生信息认证 - Android 编译脚本
# 用法: ./build_android.sh
# 输出: ./V计划学生信息认证-android-arm64
#
# 依赖: Go 1.16+ (无需 Android NDK，纯 Go 编译)
# 运行: 需将二进制推送到 Android 设备 (adb push) 并赋予执行权限

set -e

cd "$(dirname "$0")"

APP_NAME="V计划学生信息认证"
OUTPUT_NAME="${APP_NAME}-android-arm64"

echo "🔨 编译 Android ARM64 二进制..."
CGO_ENABLED=0 GOOS=android GOARCH=arm64 go build -ldflags="-s -w" -o "$OUTPUT_NAME" main.go

echo "✅ 编译完成: $(pwd)/$OUTPUT_NAME"
echo "   架构: ARM64 (aarch64)"
echo "   大小: $(du -h "$OUTPUT_NAME" | cut -f1)"
echo ""
echo "📋 部署到 Android 设备:"
echo "   1. adb push $OUTPUT_NAME /data/local/tmp/"
echo "   2. adb shell chmod +x /data/local/tmp/$OUTPUT_NAME"
echo "   3. adb shell /data/local/tmp/$OUTPUT_NAME"
echo ""
echo "   注意: 需要 root 权限或 Termux 环境运行"
