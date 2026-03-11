#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CIN_SRC="$SCRIPT_DIR/liu.cin"
CIN_DST="$HOME/Library/YabomishIM"

# Check Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    echo "⚠️  需要 Xcode Command Line Tools，正在安裝..."
    xcode-select --install
    echo "安裝完成後請重新執行 ./setup.sh"
    exit 1
fi

# Check liu.cin
if [ ! -f "$CIN_SRC" ]; then
    echo "❌ 請先將 liu.cin 放到本資料夾: $SCRIPT_DIR/"
    exit 1
fi

# Copy CIN table
mkdir -p "$CIN_DST"
cp "$CIN_SRC" "$CIN_DST/"
echo "✅ 字表已複製到 $CIN_DST/"

# Build
cd "$SCRIPT_DIR/YabomishIM"
./build.sh

# Install (needs sudo)
APP_NAME="YabomishIM"
APP_BUNDLE="$SCRIPT_DIR/YabomishIM/build/$APP_NAME.app"
INSTALL_DIR="/Library/Input Methods"

killall "$APP_NAME" 2>/dev/null || true
sleep 0.5

echo "安裝到 $INSTALL_DIR/ ..."
sudo cp -R "$APP_BUNDLE" "$INSTALL_DIR/"

echo ""
echo "✅ 完成！請到 系統設定 → 鍵盤 → 輸入方式 加入「Yabomish」"
