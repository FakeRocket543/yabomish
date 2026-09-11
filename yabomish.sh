#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

ARCH="$(uname -m)"   # 編譯 target：與 tools/release.sh 對齊（arm64 或 x86_64）

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
USER_DIR="$HOME/Library/Application Support/Yabomish"
USER_DIR_LEGACY="$HOME/Library/YabomishIM"
IM_BUNDLE_ID="com.yabomishim.inputmethod.YabomishIM"

check_xcode() {
    if ! xcode-select -p &>/dev/null; then
        warn "需要 Xcode Command Line Tools，正在安裝..."
        xcode-select --install
        err "安裝完成後請重新執行 ./yabomish.sh"
    fi
}

build_im() {
    # 編譯旗標／資源清單與 tools/release.sh 的 release 打包路徑重複——改動時兩邊需一併檢查
    local MODE="${1:-full}"
    printf "${C}> 編譯輸入法 (%s)...${N}\n" "$MODE"
    local VER; VER=$(grep '^## \[' "$ROOT/CHANGELOG.md" | grep -v '\[Unreleased\]' | head -1 | sed 's/.*\[\(.*\)\].*/\1/')
    [ -n "$VER" ] || err "無法從 CHANGELOG.md 解析版本號"   # CHANGELOG 格式漂移 → 在 rm -rf 等破壞性操作前就失敗
    rm -rf "$IM_BUILD"
    mkdir -p "$IM_APP/Contents/MacOS" "$IM_APP/Contents/Resources"

    cp "$IM_RES/Info.plist" "$IM_APP/Contents/Info.plist"
    local HASH; HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local STAMP; STAMP=$(date +%Y%m%d.%H%M)
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" "$IM_APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VER}.${STAMP}.${HASH}" "$IM_APP/Contents/Info.plist"

    # 核心資源（所有版本都包含：打字、查碼、繁簡轉換）
    for f in icon.tiff icon.icns icon_right.tiff icon_left.tiff \
             zhuyin_data.json pinyin_data.json t2s.json s2t.json \
             char_freq.json corpus_manifest.json; do
        [ -f "$IM_RES/$f" ] && cp "$IM_RES/$f" "$IM_APP/Contents/Resources/"
    done
    [ -d "$IM_RES/tables" ] && cp -R "$IM_RES/tables" "$IM_APP/Contents/Resources/"
    [ -d "$IM_RES/Plugins" ] && cp -R "$IM_RES/Plugins" "$IM_APP/Contents/Resources/"

    # 聯想／詞庫基礎語料（極簡版不含）
    if [ "$MODE" != "min" ]; then
        for f in emoji_char_map.json \
                 bigram.bin trigram.bin word_ngram.bin word_news.bin chengyu.bin \
                 phrases.bin ner_phrases.bin yoji.bin region_tw.txt region_cn.txt; do
            [ -f "$IM_RES/$f" ] && cp "$IM_RES/$f" "$IM_APP/Contents/Resources/"
        done
    fi

    # 專業詞典（完整版才包含）
    if [ "$MODE" = "full" ]; then
        for f in "$IM_RES"/terms_*.bin; do [ -f "$f" ] && cp "$f" "$IM_APP/Contents/Resources/"; done
    fi
    echo -n "APPL????" > "$IM_APP/Contents/PkgInfo"

    # 極簡版：以編譯旗標把聯想／詞庫程式碼整組移除
    local FLAGS=""
    if [ "$MODE" = "min" ]; then FLAGS="-DMINIMAL"; fi

    local SRCS=()
    while IFS= read -r f; do SRCS+=("$f"); done < <(find "$IM_SRC" -name "*.swift" | sort)
    swiftc -module-name YabomishIM \
        -target "$ARCH-apple-macos14.0" \
        -sdk "$(xcrun --show-sdk-path)" -O $FLAGS \
        -o "$IM_APP/Contents/MacOS/YabomishIM" \
        "${SRCS[@]}"

    ok "YabomishIM.app [$MODE] (build $STAMP.$HASH, $(du -sh "$IM_APP" | cut -f1))"
}

build_prefs() {
    local MODE="${1:-full}"
    printf "${C}> 編譯偏好設定 (%s)...${N}\n" "$MODE"
    local VER; VER=$(grep '^## \[' "$ROOT/CHANGELOG.md" | grep -v '\[Unreleased\]' | head -1 | sed 's/.*\[\(.*\)\].*/\1/')
    [ -n "$VER" ] || err "無法從 CHANGELOG.md 解析版本號"   # CHANGELOG 格式漂移 → 在 rm -rf 等破壞性操作前就失敗
    rm -rf "$PREFS_APP"
    mkdir -p "$PREFS_APP/Contents/MacOS" "$PREFS_APP/Contents/Resources"

    cp "$PREFS_DIR/Resources/Info.plist" "$PREFS_APP/Contents/"
    cp "$PREFS_DIR/Resources/AppIcon.icns" "$PREFS_APP/Contents/Resources/"
    [ -f "$PREFS_DIR/Resources/help.md" ] && cp "$PREFS_DIR/Resources/help.md" "$PREFS_APP/Contents/Resources/"

    local HASH; HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local STAMP; STAMP=$(date +%Y%m%d.%H%M)
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" "$PREFS_APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VER}.${STAMP}.${HASH}" "$PREFS_APP/Contents/Info.plist"
    local FLAGS=""
    if [ "$MODE" = "min" ]; then FLAGS="-DMINIMAL"; fi

    swiftc -module-name YabomishPrefs \
        -target "$ARCH-apple-macos14.0" \
        -sdk "$(xcrun --show-sdk-path)" -O $FLAGS \
        -framework SwiftUI -framework AppKit -framework UniformTypeIdentifiers \
        -o "$PREFS_APP/Contents/MacOS/YabomishPrefs" \
        "$PREFS_DIR"/Sources/*.swift

    chmod +x "$PREFS_APP/Contents/MacOS/YabomishPrefs"
    ok "YabomishPrefs.app"
}


install_im() {
    [ ! -d "$IM_APP" ] && err "請先選 1 或 2 編譯"
    sudo -v   # 預先快取 sudo 時間戳，後續連續 sudo 不會反覆要密碼
    printf "${C}> 安裝輸入法...${N}\n"
    killall YabomishIM 2>/dev/null || true; sleep 1

    # 原子式換裝：先裝 .new、再換下 .old——中途失敗不會留下「沒有輸入法」的空窗
    sudo cp -R "$IM_APP" "$INSTALL_DIR/YabomishIM.app.new"
    sudo rm -rf "$INSTALL_DIR/YabomishIM.app.old"
    [ -d "$INSTALL_DIR/YabomishIM.app" ] && sudo mv "$INSTALL_DIR/YabomishIM.app" "$INSTALL_DIR/YabomishIM.app.old"
    sudo mv "$INSTALL_DIR/YabomishIM.app.new" "$INSTALL_DIR/YabomishIM.app"
    sudo rm -rf "$INSTALL_DIR/YabomishIM.app.old"
    sudo chmod -R a+rX "$INSTALL_DIR/YabomishIM.app"
    sudo codesign -s - --force --deep "$INSTALL_DIR/YabomishIM.app" 2>/dev/null || true   # 與 all_platforms.sh macos_install 一致

    # 字表
    mkdir -p "$USER_DIR/tables"
    # emoji.txt no longer deployed — emoji handled by emoji_char_map.json suggestion system
    [ -f "$ROOT/liu.cin" ] && [ ! -f "$USER_DIR/liu.cin" ] && cp "$ROOT/liu.cin" "$USER_DIR/"

    # 自訂指令：部署 capture script + 預設 commands.json
    cp "$IM_RES/yabomish_capture.sh" "$USER_DIR/" && chmod +x "$USER_DIR/yabomish_capture.sh"
    [ ! -f "$USER_DIR/commands.json" ] && cp "$IM_RES/commands-example.json" "$USER_DIR/commands.json"

    ok "輸入法已安裝"
    [ -f "$USER_DIR/liu.cin" ] || [ -f "$USER_DIR/liu.bin" ] && ok "字表就緒" || warn "尚未偵測到字表，首次切換時會引導匯入"

    printf "${C}> 重新啟動輸入法...${N}\n"
    killall YabomishIM 2>/dev/null || true
    sleep 1

    # Force the system to re-scan input sources (imklaunchagent is blocked by
    # Launch Constraint Violation on macOS 26+ — kills TextInputMenuAgent instead)
    killall TextInputMenuAgent 2>/dev/null || true

    # Try launching directly
    open "$INSTALL_DIR/YabomishIM.app" 2>/dev/null || true
    sleep 2

    if pgrep -q YabomishIM; then
        ok "輸入法已啟動"
        ok "到 系統設定 → 鍵盤 → 輸入方式 → + → 繁體中文 → Yabomish"
    else
        warn "系統未自動啟動，請登出再登入"
    fi
}

install_prefs() {
    [ ! -d "$PREFS_APP" ] && err "請先選 1 或 2 編譯"
    printf "${C}> 安裝偏好設定...${N}\n"
    sudo -v   # 預先快取 sudo 時間戳
    # 原子式換裝（同 install_im）：先裝 .new、再換下 .old——中途失敗不會弄丟現有版本
    sudo cp -R "$PREFS_APP" /Applications/YabomishPrefs.app.new
    sudo rm -rf /Applications/YabomishPrefs.app.old
    [ -d /Applications/YabomishPrefs.app ] && sudo mv /Applications/YabomishPrefs.app /Applications/YabomishPrefs.app.old
    sudo mv /Applications/YabomishPrefs.app.new /Applications/YabomishPrefs.app
    sudo rm -rf /Applications/YabomishPrefs.app.old
    sudo chmod -R a+rX /Applications/YabomishPrefs.app
    ok "YabomishPrefs.app -> /Applications/"
}

do_uninstall() {
    # $1 = 1（CLI --yes）：跳過所有確認，連使用者資料一併刪除
    local ASSUME_YES="${1:-0}"
    if [ "$ASSUME_YES" != "1" ]; then
        printf "確定要移除 Yabomish？[y/N] "; read -r c || c=""
        [[ "$c" =~ ^[Yy]$ ]] || { echo "已取消。"; return 0; }
    fi
    killall YabomishIM 2>/dev/null || true
    killall YabomishPrefs 2>/dev/null || true
    sleep 0.5
    sudo rm -rf "$INSTALL_DIR/YabomishIM.app"
    sudo rm -rf "$HOME/Library/Input Methods/YabomishIM.app"   # all_platforms.sh 裝在使用者層級的副本
    sudo rm -rf /Applications/YabomishPrefs.app
    defaults delete $IM_BUNDLE_ID 2>/dev/null || true
    local WIPE="n"
    if [ "$ASSUME_YES" = "1" ]; then
        WIPE="y"
    else
        printf "一併刪除使用者資料（字表、字頻）？[y/N] "; read -r c || c=""
        [[ "$c" =~ ^[Yy]$ ]] && WIPE="y"
    fi
    if [ "$WIPE" = "y" ]; then
        rm -rf "$USER_DIR" && echo "已刪除 $USER_DIR"
        rm -rf "$USER_DIR_LEGACY" 2>/dev/null && echo "已刪除 $USER_DIR_LEGACY"
    fi
    ok "移除完成，請登出再登入"
}

ask_mode() {
    printf "  1) 完整（含 28 專業詞典，~98MB）\n"
    printf "  2) 精簡（省空間，無專業詞典，仍有成語、用語、兩岸用詞聯想，~18MB）\n"
    printf "  3) 極簡（無聯想、無詞庫，僅打字＋查碼＋繁簡轉換，~2MB）\n"
    printf "  （語料 .bin 不隨 repo：全新 clone 會在安裝時自 GitHub Release 下載）\n"
    printf "  選擇 [1/2/3, Enter=完整]: "; read -r m || m=""   # EOF（管線輸入結束）→ 視為 Enter，採預設完整版
    case "$m" in 2) BUILD_MODE="lite";; 3) BUILD_MODE="min";; *) BUILD_MODE="full";; esac
}

# 全新 clone 沒有語料 bin（*.bin 為 gitignore）：從 GitHub Release 下載對應等級的
# 語料包到 Resources，讓完整/精簡對原始碼安裝者產生實質差異。
# 本地已有 bin（開發機）→ 跳過；下載失敗（離線／Release 未發佈）→ 不中斷，
# App 會在首次打字時自動重試（DataDownloader 同一 manifest）。
corpus_ready() {
    # 判斷本地語料是否齊全。corpus_manifest.json 只有下載網址與雜湊、沒有檔案清單，
    # 改用各等級的標記檔逐檔判定（清單與 build_im 的複製清單一致）。
    local MODE="$1" f
    for f in bigram.bin trigram.bin word_ngram.bin word_news.bin chengyu.bin \
             phrases.bin ner_phrases.bin yoji.bin region_tw.txt region_cn.txt; do
        [ -f "$IM_RES/$f" ] || return 1
    done
    if [ "$MODE" = "full" ]; then
        compgen -G "$IM_RES/terms_*.bin" >/dev/null || return 1
    fi
    return 0
}

fetch_corpus() {
    local MODE="${1:-full}"
    [ "$MODE" = "min" ] && return 0
    local MANIFEST="$IM_RES/corpus_manifest.json"
    [ -f "$MANIFEST" ] || { warn "找不到 corpus_manifest.json，略過語料下載"; return 0; }
    corpus_ready "$MODE" && return 0   # 本地已備齊（逐檔檢查，不再只看「有沒有任一 .bin」）

    local URL SHA
    read -r URL SHA < <(python3 - "$MANIFEST" "$MODE" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
if sys.argv[2] == "full" and "full" in m:
    print(m["full"]["url"], m["full"]["sha256"])
else:
    print(m["url"], m["sha256"])
PY
) || true   # 解析失敗 → URL 為空，由下一行統一處理
    [ -n "$URL" ] || { warn "manifest 未含 $MODE 語料段，略過"; return 0; }

    local TMPZIP="$ROOT/build/corpus_dl.zip"
    mkdir -p "$ROOT/build"
    printf "${C}> 下載語料包（%s）...${N}\n" "$(basename "$URL")"
    # -C -：上次下載到一半的檔案可續傳，不會從頭來
    if ! curl -fSL -C - --progress-bar -o "$TMPZIP" "$URL"; then
        # 續傳失敗（伺服器不支援範圍請求、或檔案其實已下載完整）→ 清掉重試一次
        rm -f "$TMPZIP"
        if ! curl -fSL --progress-bar -o "$TMPZIP" "$URL"; then
            rm -f "$TMPZIP"
            warn "語料下載失敗（離線或 Release 尚未發佈）——首次打字時會自動重試"
            return 0
        fi
    fi
    local GOT; GOT=$(shasum -a 256 "$TMPZIP" | awk '{print $1}')
    if [ "$GOT" != "$SHA" ]; then
        rm -f "$TMPZIP"; warn "語料雜湊不符，略過（下載損毀？）"; return 0
    fi
    # 先解壓到 staging、只搬預期的語料檔（*.bin、region_*.txt）進 Resources：
    # 壞 zip 不會覆寫 Info.plist／corpus_manifest.json（同 DataDownloader 的 staging 做法）
    local STAGING="$ROOT/build/corpus_staging" f
    rm -rf "$STAGING"
    mkdir -p "$STAGING"
    if ! unzip -oq "$TMPZIP" -d "$STAGING"; then
        rm -rf "$STAGING" "$TMPZIP"
        warn "語料解壓失敗，略過"; return 0
    fi
    for f in "$STAGING"/*.bin "$STAGING"/region_*.txt; do
        [ -e "$f" ] || continue
        mv -f "$f" "$IM_RES/"
    done
    rm -rf "$STAGING" "$TMPZIP"
    local BINS=0
    for f in "$IM_RES"/*.bin; do [ -e "$f" ] && BINS=$((BINS + 1)); done
    ok "語料就緒（${BINS} 個 bin）"
}

show_menu() {
    printf "\n${B}Yabomish 管理工具${N}\n"
    echo "-----------------------------"
    printf "  ${B}1)${N} 編譯 + 安裝\n"
    printf "  ${B}2)${N} 只編譯（不安裝）\n"
    printf "  ${B}3)${N} 只安裝（已編譯過）\n"
    printf "  ${B}4)${N} 快速重裝偏好設定\n"
    printf "  ${B}5)${N} 移除 Yabomish\n"
    printf "  ${B}T)${N} 執行測試\n"
    printf "  ${B}0)${N} 離開\n"
    echo "-----------------------------"
    printf "選擇: "
}

usage() {
    cat >&2 <<'EOF'
用法: ./yabomish.sh                       互動選單
      ./yabomish.sh build [full|lite|min] 編譯輸入法＋偏好設定（預設 full）
      ./yabomish.sh install               安裝輸入法＋偏好設定
      ./yabomish.sh uninstall [--yes]     移除（--yes 跳過所有確認，連使用者資料一起刪）
      ./yabomish.sh test                  執行測試（YabomishIM/Tests/run_tests.sh）
EOF
}

# 在子殼層執行選單動作：err（exit 1）或任一步驟失敗只回報、不關閉選單迴圈。
# CLI 子命令不走這裡，err 仍會直接離開腳本。
menu_run() {
    if ! ( "$@" ); then
        warn "步驟失敗，已回到主選單"
    fi
    return 0
}

# 選單動作組合：&& 串接保證前一步失敗就停，不會裝到半套
do_build() {
    fetch_corpus "$BUILD_MODE" && build_im "$BUILD_MODE" && build_prefs "$BUILD_MODE"
}

do_install() {
    install_im && install_prefs
}

do_prefs() {
    build_prefs && install_prefs
}

do_build_install() {
    do_build && do_install
}

# CLI 子命令：無參數 → 落到下方互動選單。子命令完全免互動；
# Xcode CLT 檢查只在會編譯的路徑（build／選單）需要。
case "${1:-}" in
    "") ;;
    build)
        [ $# -le 2 ] || { usage; exit 2; }
        MODE="${2:-full}"
        case "$MODE" in full|lite|min) ;; *) usage; exit 2;; esac
        check_xcode
        fetch_corpus "$MODE"
        build_im "$MODE"
        build_prefs "$MODE"
        exit 0
        ;;
    install)
        [ $# -eq 1 ] || { usage; exit 2; }
        install_im
        install_prefs
        exit 0
        ;;
    uninstall)
        if [ $# -eq 2 ] && [ "$2" = "--yes" ]; then
            do_uninstall 1
        elif [ $# -eq 1 ]; then
            do_uninstall 0
        else
            usage
            exit 2
        fi
        exit 0
        ;;
    test)
        [ $# -eq 1 ] || { usage; exit 2; }
        exec bash "$ROOT/YabomishIM/Tests/run_tests.sh"
        ;;
    *)
        usage
        exit 2
        ;;
esac

# 選單路徑可編譯 → 維持 CLT 檢查（CLI 的 install/uninstall/test 不再需要 CLT）
check_xcode
while true; do
    show_menu
    read -r choice || { echo ""; break; }   # EOF（管線輸入結束）→ 正常離開，不被 set -e 殺掉
    echo ""
    case "$choice" in
        1) ask_mode; menu_run do_build_install;;
        2) ask_mode; menu_run do_build;;
        3) menu_run do_install;;
        4) menu_run do_prefs;;
        5) menu_run do_uninstall;;
        t|T) menu_run bash "$ROOT/YabomishIM/Tests/run_tests.sh";;
        0) echo "Bye!"; exit 0;;
        *) warn "請輸入 0-5 或 T";;
    esac
done
