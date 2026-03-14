#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    echo "⚠️  需要 Xcode Command Line Tools，正在安裝..."
    xcode-select --install
    echo "安裝完成後請重新執行 ./setup.sh"
    exit 1
fi

# Build + Install (install.sh handles sudo, icon/label menus)
cd "$SCRIPT_DIR/YabomishIM"
bash build.sh
bash install.sh

echo ""
echo "✅ 完成！請到 系統設定 → 鍵盤 → 輸入方式 加入「Yabomish」"
echo "   首次切換到 Yabomish 時會引導你匯入 liu.cin 字表。"
