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
[ "$LABEL_PREF" = "yabo" ] && LABEL_CUR="Yabo"
echo ""
echo "狀態列顯示名稱（目前: $LABEL_CUR）："
echo "  1) Yabo"
echo "  2) Yabomish"
printf "選擇 [1/2，Enter 保持]: "
read -r choice
case "$choice" in
    1) LABEL_PREF="yabo" ;;
    2) LABEL_PREF="yabomish" ;;
esac
defaults write com.yabomishim.inputmethod.YabomishIM menuBarLabel "$LABEL_PREF"
case "$LABEL_PREF" in
    yabo)
        sudo /usr/libexec/PlistBuddy -c "Set :CFBundleName Yabo" "$PLIST"
        echo "📛 狀態列: Yabo"
        ;;
    *)
        sudo /usr/libexec/PlistBuddy -c "Set :CFBundleName Yabomish" "$PLIST"
        echo "📛 狀態列: Yabomish"
        ;;
esac

# Ensure user CIN directory and tables
mkdir -p "$USER_CIN_DIR"
mkdir -p "$USER_CIN_DIR/tables"

# Copy bundled extra tables (emoji etc.)
TABLES_SRC="$SCRIPT_DIR/Resources/tables"
if [ -d "$TABLES_SRC" ]; then
    for f in "$TABLES_SRC"/*.txt; do
        [ -f "$f" ] && [[ "$(basename "$f")" != *-example* ]] && cp "$f" "$USER_CIN_DIR/tables/"
    done
    echo "✅ 擴充表已安裝到 $USER_CIN_DIR/tables/"
fi

# 如果專案根目錄有 liu.cin，自動複製
PROJECT_CIN="$SCRIPT_DIR/../liu.cin"
if [ -f "$PROJECT_CIN" ] && [ ! -f "$USER_CIN_DIR/liu.cin" ]; then
    cp "$PROJECT_CIN" "$USER_CIN_DIR/"
    echo "✅ 已從專案目錄匯入字表到 $USER_CIN_DIR/"
fi

if [ -f "$USER_CIN_DIR/liu.cin" ]; then
    echo "✅ 字表就緒: $USER_CIN_DIR/liu.cin"
else
    echo ""
    echo "⚠️  尚未偵測到字表！"
    echo "   首次切換到 Yabomish 時會引導你匯入 liu.cin。"
fi

echo ""
echo "✅ 安裝完成！"
echo "   請登出再登入，或到 系統設定 → 鍵盤 → 輸入方式 加入「Yabomish」"
