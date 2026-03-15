#!/bin/bash
set -e

APP_NAME="YabomishIM"
INSTALL_DIR="/Library/Input Methods"
USER_DATA_DIR="$HOME/Library/YabomishIM"
BUNDLE_ID="com.yabomishim.inputmethod.YabomishIM"

echo "🗑  移除 Yabomish 輸入法"
echo ""

# Kill process
killall "$APP_NAME" 2>/dev/null || true
sleep 0.5

# Remove app bundle
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    sudo rm -rf "$INSTALL_DIR/$APP_NAME.app"
    echo "✅ 已移除 $INSTALL_DIR/$APP_NAME.app"
else
    echo "ℹ️  $INSTALL_DIR/$APP_NAME.app 不存在，跳過"
fi

# Remove defaults
if defaults read "$BUNDLE_ID" &>/dev/null; then
    defaults delete "$BUNDLE_ID"
    echo "✅ 已清除偏好設定"
fi

# Ask about user data
if [ -d "$USER_DATA_DIR" ]; then
    echo ""
    echo "⚠️  發現使用者資料: $USER_DATA_DIR"
    printf "   是否一併刪除？(y/N): "
    read -r ans
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
        rm -rf "$USER_DATA_DIR"
        echo "✅ 已移除使用者資料"
    else
        echo "ℹ️  保留使用者資料"
    fi
fi

echo ""
echo "✅ 移除完成！請登出再登入以完全生效。"
