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

# 蝦頭方向選擇
ICON_DIR="$INSTALL_DIR/$APP_NAME.app/Contents/Resources"
ICON_PREF=$(defaults read com.yabomishim.inputmethod.YabomishIM iconDirection 2>/dev/null || echo "left")
ICON_CUR="← 向左"
[ "$ICON_PREF" = "right" ] && ICON_CUR="→ 向右"
echo ""
echo "蝦頭方向（目前: $ICON_CUR）："
echo "  1) ← 向左"
echo "  2) → 向右"
printf "選擇 [1/2，Enter 保持]: "
read -r choice
case "$choice" in
    1) ICON_PREF="left" ;;
    2) ICON_PREF="right" ;;
esac
defaults write com.yabomishim.inputmethod.YabomishIM iconDirection "$ICON_PREF"
if [ "$ICON_PREF" = "right" ] && [ -f "$ICON_DIR/icon_right.tiff" ]; then
    sudo cp "$ICON_DIR/icon_right.tiff" "$ICON_DIR/icon.tiff"
    echo "🦐 蝦頭方向: → 向右"
else
    echo "🦐 蝦頭方向: ← 向左"
fi

# 狀態列名稱選擇
PLIST="$INSTALL_DIR/$APP_NAME.app/Contents/Info.plist"
LABEL_PREF=$(defaults read com.yabomishim.inputmethod.YabomishIM menuBarLabel 2>/dev/null || echo "yabomish")
LABEL_CUR="Yabomish"
[ "$LABEL_PREF" = "icon" ] && LABEL_CUR="僅圖示"
[ "$LABEL_PREF" = "yabo" ] && LABEL_CUR="Yabo"
echo ""
echo "狀態列顯示名稱（目前: $LABEL_CUR）："
echo "  1) 僅圖示"
echo "  2) Yabo"
echo "  3) Yabomish"
printf "選擇 [1/2/3，Enter 保持]: "
read -r choice
case "$choice" in
    1) LABEL_PREF="icon" ;;
    2) LABEL_PREF="yabo" ;;
    3) LABEL_PREF="yabomish" ;;
esac
defaults write com.yabomishim.inputmethod.YabomishIM menuBarLabel "$LABEL_PREF"
case "$LABEL_PREF" in
    icon)
        sudo /usr/libexec/PlistBuddy -c "Set :CFBundleName ''" "$PLIST"
        echo "📛 狀態列: 僅圖示"
        ;;
    yabo)
        sudo /usr/libexec/PlistBuddy -c "Set :CFBundleName Yabo" "$PLIST"
        echo "📛 狀態列: Yabo"
        ;;
    *)
        echo "📛 狀態列: Yabomish"
        ;;
esac

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
