#!/bin/bash
# Yabomish 安裝腳本 — 從 DMG 或專案目錄執行
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="YabomishIM"
INSTALL_DIR="/Library/Input Methods"

# 找 app bundle（DMG 裡或 build 目錄）
if [ -d "$SCRIPT_DIR/$APP_NAME.app" ]; then
    APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
elif [ -d "$SCRIPT_DIR/YabomishIM/build/$APP_NAME.app" ]; then
    APP_BUNDLE="$SCRIPT_DIR/YabomishIM/build/$APP_NAME.app"
else
    echo "❌ 找不到 $APP_NAME.app"
    echo "   請先執行 build.sh 或從 DMG 開啟"
    exit 1
fi

echo "🦐 Yabomish 安裝程式"
echo ""

# Kill existing
killall "$APP_NAME" 2>/dev/null || true
sleep 0.5

# Install
echo "安裝到 $INSTALL_DIR/ ..."
sudo cp -R "$APP_BUNDLE" "$INSTALL_DIR/"
sudo chmod -R a+rX "$INSTALL_DIR/$APP_NAME.app"

# 蝦頭方向
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

# 狀態列名稱
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

# 字表檢查
USER_CIN_DIR="$HOME/Library/YabomishIM"
mkdir -p "$USER_CIN_DIR"

# 如果同目錄有 liu.cin（DMG 或專案根目錄），自動複製
if [ -f "$SCRIPT_DIR/liu.cin" ] && [ ! -f "$USER_CIN_DIR/liu.cin" ]; then
    cp "$SCRIPT_DIR/liu.cin" "$USER_CIN_DIR/"
    echo "✅ 已從安裝目錄匯入字表到 $USER_CIN_DIR/"
fi

if [ -f "$USER_CIN_DIR/liu.cin" ]; then
    echo "✅ 字表就緒: $USER_CIN_DIR/liu.cin"
else
    echo ""
    echo "⚠️  尚未偵測到字表"
    echo "   首次切換到 Yabomish 時會引導你匯入 liu.cin。"
fi

# Deploy bundled extra tables (emoji etc.)
mkdir -p "$USER_CIN_DIR/tables"
TABLES_SRC="$INSTALL_DIR/$APP_NAME.app/Contents/Resources/tables"
if [ -d "$TABLES_SRC" ]; then
    for f in "$TABLES_SRC"/*.txt; do
        [ -f "$f" ] && [[ "$(basename "$f")" != *-example* ]] && cp "$f" "$USER_CIN_DIR/tables/"
    done
    echo "✅ 擴充表已安裝到 $USER_CIN_DIR/tables/"
fi

echo ""
echo "✅ 安裝完成！"
echo "   請登出再登入，或到 系統設定 → 鍵盤 → 輸入方式 加入「Yabomish」"
echo ""
read -rp "按 Enter 關閉⋯"
