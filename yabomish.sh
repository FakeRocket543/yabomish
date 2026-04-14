#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

G='\033[32m'; Y='\033[33m'; R='\033[31m'; C='\033[36m'; B='\033[1m'; N='\033[0m'
ok()   { printf "${G}[OK] %s${N}\n" "$1"; }
warn() { printf "${Y}[!!] %s${N}\n" "$1"; }
err()  { printf "${R}[ERR] %s${N}\n" "$1"; exit 1; }

IM_SRC="$ROOT/YabomishIM/Sources"
IM_RES="$ROOT/YabomishIM/Resources"
IM_BUILD="$ROOT/YabomishIM/build"
IM_APP="$IM_BUILD/YabomishIM.app"
PREFS_DIR="$ROOT/YabomishPrefs"
PREFS_APP="$PREFS_DIR/YabomishPrefs.app"
INSTALL_DIR="/Library/Input Methods"
USER_DIR="$HOME/Library/YabomishIM"
IM_BUNDLE_ID="com.yabomishim.inputmethod.YabomishIM"

check_xcode() {
    if ! xcode-select -p &>/dev/null; then
        warn "需要 Xcode Command Line Tools，正在安裝..."
        xcode-select --install
        err "安裝完成後請重新執行 ./yabomish.sh"
    fi
}

build_im() {
    local MODE="${1:-full}"
    printf "${C}> 編譯輸入法 (%s)...${N}\n" "$MODE"
    rm -rf "$IM_BUILD"
    mkdir -p "$IM_APP/Contents/MacOS" "$IM_APP/Contents/Resources"

    cp "$IM_RES/Info.plist" "$IM_APP/Contents/Info.plist"
    local VER; VER=$(grep -m1 '^## \[' "$ROOT/CHANGELOG.md" | sed 's/.*\[\(.*\)\].*/\1/')
    local HASH; HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local STAMP; STAMP=$(date +%Y%m%d.%H%M)
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VER}.${STAMP}.${HASH}" "$IM_APP/Contents/Info.plist"

    # 核心資源（精簡版也包含）
    for f in icon.tiff icon.icns icon_right.tiff icon_left.tiff \
             zhuyin_data.json pinyin_data.json t2s.json s2t.json emoji_char_map.json \
             char_freq.json; do
        [ -f "$IM_RES/$f" ] && cp "$IM_RES/$f" "$IM_APP/Contents/Resources/"
    done
    [ -d "$IM_RES/tables" ] && cp -R "$IM_RES/tables" "$IM_APP/Contents/Resources/"

    # 基礎語料（精簡版也包含：聯想、成語、兩岸用詞）
    for f in bigram.bin trigram.bin word_ngram.bin word_news.bin chengyu.bin \
             phrases.bin ner_phrases.bin yoji.bin region_tw.txt region_cn.txt; do
        [ -f "$IM_RES/$f" ] && cp "$IM_RES/$f" "$IM_APP/Contents/Resources/"
    done

    # 專業詞典（完整版才包含）
    if [ "$MODE" = "full" ]; then
        for f in "$IM_RES"/terms_*.bin; do [ -f "$f" ] && cp "$f" "$IM_APP/Contents/Resources/"; done
    fi
    echo -n "APPL????" > "$IM_APP/Contents/PkgInfo"

    swiftc -module-name YabomishIM \
        -target arm64-apple-macos14.0 \
        -sdk "$(xcrun --show-sdk-path)" -O \
        -o "$IM_APP/Contents/MacOS/YabomishIM" \
        $(find "$IM_SRC" -name "*.swift" | sort)

    ok "YabomishIM.app [$MODE] (build $STAMP.$HASH, $(du -sh "$IM_APP" | cut -f1))"
}

build_prefs() {
    printf "${C}> 編譯偏好設定...${N}\n"
    rm -rf "$PREFS_APP"
    mkdir -p "$PREFS_APP/Contents/MacOS" "$PREFS_APP/Contents/Resources"

    cp "$PREFS_DIR/Resources/Info.plist" "$PREFS_APP/Contents/"
    cp "$PREFS_DIR/Resources/AppIcon.icns" "$PREFS_APP/Contents/Resources/"

    swiftc -module-name YabomishPrefs \
        -target arm64-apple-macos14.0 \
        -sdk "$(xcrun --show-sdk-path)" -O \
        -framework SwiftUI -framework AppKit -framework UniformTypeIdentifiers \
        -o "$PREFS_APP/Contents/MacOS/YabomishPrefs" \
        "$PREFS_DIR"/Sources/*.swift

    chmod +x "$PREFS_APP/Contents/MacOS/YabomishPrefs"
    ok "YabomishPrefs.app"
}

install_im() {
    [ ! -d "$IM_APP" ] && err "請先選 1 或 2 編譯"
    printf "${C}> 安裝輸入法...${N}\n"
    killall YabomishIM 2>/dev/null || true; sleep 1

    sudo cp -R "$IM_APP" "$INSTALL_DIR/"
    sudo chmod -R a+rX "$INSTALL_DIR/YabomishIM.app"

    # 蝦頭方向
    local DIR="$INSTALL_DIR/YabomishIM.app/Contents/Resources"
    local ICON; ICON=$(defaults read $IM_BUNDLE_ID iconDirection 2>/dev/null || echo "left")
    local CUR="<- 向左"; [ "$ICON" = "right" ] && CUR="-> 向右"
    echo ""
    echo "蝦頭方向 (目前: $CUR):  1) <- 向左  2) -> 向右"
    printf "選擇 [1/2, Enter 保持]: "; read -r c
    case "$c" in 1) ICON="left";; 2) ICON="right";; esac
    defaults write $IM_BUNDLE_ID iconDirection "$ICON"
    [ "$ICON" = "right" ] && [ -f "$DIR/icon_right.tiff" ] && sudo cp "$DIR/icon_right.tiff" "$DIR/icon.tiff"

    # 狀態列名稱
    local PLIST="$INSTALL_DIR/YabomishIM.app/Contents/Info.plist"
    local LBL; LBL=$(defaults read $IM_BUNDLE_ID menuBarLabel 2>/dev/null || echo "yabomish")
    local LCUR="Yabomish"; [ "$LBL" = "yabo" ] && LCUR="Yabo"
    echo ""
    echo "狀態列名稱 (目前: $LCUR):  1) Yabo  2) Yabomish"
    printf "選擇 [1/2, Enter 保持]: "; read -r c
    case "$c" in 1) LBL="yabo";; 2) LBL="yabomish";; esac
    defaults write $IM_BUNDLE_ID menuBarLabel "$LBL"
    case "$LBL" in
        yabo) sudo /usr/libexec/PlistBuddy -c "Set :CFBundleName Yabo" "$PLIST";;
        *)    sudo /usr/libexec/PlistBuddy -c "Set :CFBundleName Yabomish" "$PLIST";;
    esac

    # 字表
    mkdir -p "$USER_DIR/tables"
    # emoji.txt no longer deployed — emoji handled by emoji_char_map.json suggestion system
    [ -f "$ROOT/liu.cin" ] && [ ! -f "$USER_DIR/liu.cin" ] && cp "$ROOT/liu.cin" "$USER_DIR/"

    ok "輸入法已安裝"
    [ -f "$USER_DIR/liu.cin" ] && ok "字表就緒" || warn "尚未偵測到字表，首次切換時會引導匯入"

    printf "${C}> 重新啟動輸入法...${N}\n"
    killall YabomishIM 2>/dev/null || true
    sleep 2
    if pgrep -q YabomishIM; then
        ok "輸入法已重新啟動，不需登出"
    else
        warn "系統未自動重啟，請登出再登入"
    fi
}

install_prefs() {
    [ ! -d "$PREFS_APP" ] && err "請先選 1 或 2 編譯"
    printf "${C}> 安裝偏好設定...${N}\n"
    cp -R "$PREFS_APP" /Applications/
    ok "YabomishPrefs.app -> /Applications/"
}

do_uninstall() {
    printf "確定要移除 Yabomish？[y/N] "; read -r c
    [[ "$c" =~ ^[Yy]$ ]] || { echo "已取消。"; return; }
    killall YabomishIM 2>/dev/null || true; sleep 0.5
    sudo rm -rf "$INSTALL_DIR/YabomishIM.app"
    rm -rf /Applications/YabomishPrefs.app
    defaults delete $IM_BUNDLE_ID 2>/dev/null || true
    printf "一併刪除使用者資料（字表、字頻）？[y/N] "; read -r c
    [[ "$c" =~ ^[Yy]$ ]] && rm -rf "$USER_DIR" && echo "已刪除 $USER_DIR"
    ok "移除完成，請登出再登入"
}

ask_mode() {
    printf "  1) 完整（含 28 專業詞典，~98MB）  2) 精簡（基礎聯想，~18MB）\n"
    printf "  選擇 [1/2, Enter=完整]: "; read -r m
    case "$m" in 2) echo "lite";; *) echo "full";; esac
}

show_menu() {
    printf "\n${B}Yabomish 管理工具${N}\n"
    echo "-----------------------------"
    printf "  ${B}1)${N} 編譯 + 安裝\n"
    printf "  ${B}2)${N} 只編譯（不安裝）\n"
    printf "  ${B}3)${N} 只安裝（已編譯過）\n"
    printf "  ${B}4)${N} 快速重裝偏好設定\n"
    printf "  ${B}5)${N} 移除 Yabomish\n"
    printf "  ${B}0)${N} 離開\n"
    echo "-----------------------------"
    printf "選擇: "
}

check_xcode
while true; do
    show_menu; read -r choice; echo ""
    case "$choice" in
        1) M=$(ask_mode); build_im "$M"; build_prefs; install_im; install_prefs;;
        2) M=$(ask_mode); build_im "$M"; build_prefs;;
        3) install_im; install_prefs;;
        4) build_prefs; install_prefs;;
        5) do_uninstall;;
        0) echo "Bye!"; exit 0;;
        *) warn "請輸入 0-5";;
    esac
done
