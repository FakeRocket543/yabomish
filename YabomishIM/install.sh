#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="YabomishIM"
APP_BUNDLE="$SCRIPT_DIR/build/$APP_NAME.app"
INSTALL_DIR="/Library/Input Methods"
USER_CIN_DIR="$HOME/Library/YabomishIM"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "錯誤: 請先執行 ./build.sh"
    exit 1
fi

# Kill existing process
killall "$APP_NAME" 2>/dev/null || true
sleep 0.5

# Install
echo "安裝到 $INSTALL_DIR/ ..."
sudo cp -R "$APP_BUNDLE" "$INSTALL_DIR/"
sudo chmod -R  a+rX "$INSTALL_DIR/$APP_NAME.app"

# Ensure user CIN directory and check for liu.cin
mkdir -p "$USER_CIN_DIR"

if [ ! -f "$USER_CIN_DIR/liu.cin" ]; then
    echo ""
    echo "⚠️  尚未偵測到字表！"
    echo "   請將 liu.cin 複製到: $USER_CIN_DIR/"
    echo ""
    echo "   cp /你的/liu.cin路徑 $USER_CIN_DIR/"
    echo ""
    echo "   沒有字表將無法輸入中文。"
else
    echo "✅ 已偵測到字表: $USER_CIN_DIR/liu.cin"
fi

echo ""
echo "✅ 安裝完成！"
echo "   請登出再登入，或到 系統設定 → 鍵盤 → 輸入方式 加入「Yabomish」"
