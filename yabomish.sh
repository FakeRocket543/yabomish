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
# YABOMISH_DEV=1 產生獨立實驗變體：不同 bundle ID / app 名 / App Support 目錄，
# 與 stable 並存互不干擾（dev 搞壞輸入法時 stable 仍可打字）。
# dev 裝在 ~/Library/Input Methods：免 sudo、不碰系統目錄，可全自動安裝測試。
if [ "${YABOMISH_DEV:-0}" = "1" ]; then
    # YABOMISH_APP/YABOMISH_BID 可再覆寫名稱與 ID：本機殘留同 ID 舊 bundle 時
    # 用不同 ID 再開一個變體測試（產品預設仍是 YabomishDev / …IMDev）。
    IM_APP_NAME="${YABOMISH_APP:-YabomishDev}"
    IM_BUNDLE_ID="${YABOMISH_BID:-com.yabomishim.inputmethod.YabomishIMDev}"
    USER_DIR="$HOME/Library/Application Support/$IM_APP_NAME"
    INSTALL_DIR="$HOME/Library/Input Methods"
    SUDO=""
else
    IM_APP_NAME="YabomishIM"
    IM_BUNDLE_ID="com.yabomishim.inputmethod.YabomishIM"
    USER_DIR="$HOME/Library/Application Support/Yabomish"
    INSTALL_DIR="/Library/Input Methods"
    SUDO="sudo"
fi
# build 產物故意不用 .app 副檔名：留在專案目錄的 .app 會被 LaunchServices/TIS
# 註冊成另一個同名輸入法來源，Settings 與輸入法選單會長出重複的 YabomishDev。
IM_APP="$IM_BUILD/$IM_APP_NAME.appbuild"
PREFS_DIR="$ROOT/YabomishPrefs"
PREFS_APP="$PREFS_DIR/YabomishPrefs.app"
USER_DIR_LEGACY="$HOME/Library/YabomishIM"

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
    if [ "$IM_APP_NAME" != "YabomishIM" ]; then
        # dev 變體：bundle ID 全文替換（含 ComponentInputModeDict 的 mode ID/InputSourceID、連線名）
        sed -i '' "s/com.yabomishim.inputmethod.YabomishIM/$IM_BUNDLE_ID/g" "$IM_APP/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Set :CFBundleName $IM_APP_NAME" "$IM_APP/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $IM_APP_NAME" "$IM_APP/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $IM_APP_NAME" "$IM_APP/Contents/Info.plist"
        # dev 中文 mode 用 β 圖示與 stable 蝦字圖示視覺區分；英文 mode 維持 icon_en.tiff
        /usr/libexec/PlistBuddy -c "Set :tsInputMethodIconFileKey icon_dev.tiff" "$IM_APP/Contents/Info.plist"
        for k in tsInputModeIconFileKey tsInputModeMenuIconFileKey tsInputModePaletteIconFileKey; do
            /usr/libexec/PlistBuddy -c "Set :ComponentInputModeDict:tsInputModeListKey:$IM_BUNDLE_ID:$k icon_dev.tiff" "$IM_APP/Contents/Info.plist"
        done
        cp "$IM_RES/icon_dev.tiff" "$IM_APP/Contents/Resources/"
        # dev app icon 用剪影版（β 角標），與 stable 彩色炸蝦在 Dock/Finder 區分
        /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile icon_dev.icns" "$IM_APP/Contents/Info.plist"
        cp "$IM_RES/icon_dev.icns" "$IM_APP/Contents/Resources/"
    fi
    local HASH; HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local STAMP; STAMP=$(date +%Y%m%d.%H%M)
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" "$IM_APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VER}.${STAMP}.${HASH}" "$IM_APP/Contents/Info.plist"

    # 核心資源（所有版本都包含：打字、查碼、繁簡轉換）
    for f in icon.tiff icon_en.tiff icon.icns \
             zhuyin_data.json pinyin_data.json t2s.json s2t.json \
             char_freq.json corpus_manifest.json english_10k.txt; do
        [ -f "$IM_RES/$f" ] && cp "$IM_RES/$f" "$IM_APP/Contents/Resources/"
    done
    [ -d "$IM_RES/tables" ] && cp -R "$IM_RES/tables" "$IM_APP/Contents/Resources/"
    [ -d "$IM_RES/Plugins" ] && cp -R "$IM_RES/Plugins" "$IM_APP/Contents/Resources/"

    # mode 名稱本地化（輸入法選單名稱走 InfoPlist.loctable，非 .lproj）；
    # dev 變體需把 key 裡的 bundle ID 一併改名
    if [ -f "$IM_RES/InfoPlist.loctable" ]; then
        # key 的 bundle ID 跟 Info.plist 同步改名；value 的顯示名加 Dev 以便與 stable 區分
        sed -e "s/com.yabomishim.inputmethod.YabomishIM/${IM_BUNDLE_ID}/g" \
            -e "s/>Yabomish</>${IM_APP_NAME}</g" \
            "$IM_RES/InfoPlist.loctable" > "$IM_APP/Contents/Resources/InfoPlist.loctable"
    fi

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
        -o "$IM_APP/Contents/MacOS/$IM_APP_NAME" \
        "${SRCS[@]}"

    ok "$IM_APP_NAME.app [$MODE] (build $STAMP.$HASH, $(du -sh "$IM_APP" | cut -f1))"
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
    if [ "${YABOMISH_DEV:-0}" = "1" ]; then
        # dev 設定程式用剪影版圖示
        /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIconDev" "$PREFS_APP/Contents/Info.plist"
        cp "$PREFS_DIR/Resources/AppIconDev.icns" "$PREFS_APP/Contents/Resources/"
    fi
    [ -f "$PREFS_DIR/Resources/help.md" ] && cp "$PREFS_DIR/Resources/help.md" "$PREFS_APP/Contents/Resources/"

    local HASH; HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local STAMP; STAMP=$(date +%Y%m%d.%H%M)
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" "$PREFS_APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VER}.${STAMP}.${HASH}" "$PREFS_APP/Contents/Info.plist"
    local FLAGS=""
    if [ "$MODE" = "min" ]; then FLAGS="-DMINIMAL"; fi

    # Shared/UserEnglishDict.swift 與 IM 共用（英數頁的自訂詞清單）——
    # 該檔 init 帶目錄、不依賴 AppConstants，兩個 target 都能編。
    swiftc -module-name YabomishPrefs \
        -target "$ARCH-apple-macos14.0" \
        -sdk "$(xcrun --show-sdk-path)" -O $FLAGS \
        -framework SwiftUI -framework AppKit -framework UniformTypeIdentifiers \
        -o "$PREFS_APP/Contents/MacOS/YabomishPrefs" \
        "$PREFS_DIR"/Sources/*.swift \
        "$IM_SRC/Shared/UserEnglishDict.swift"

    chmod +x "$PREFS_APP/Contents/MacOS/YabomishPrefs"
    ok "YabomishPrefs.app"
}


install_im() {
    [ ! -d "$IM_APP" ] && err "請先選 1 或 2 編譯"
    [ -n "$SUDO" ] && sudo -v   # 預先快取 sudo 時間戳，後續連續 sudo 不會反覆要密碼
    printf "${C}> 安裝輸入法...${N}\n"
    killall "$IM_APP_NAME" 2>/dev/null || true; sleep 1
    mkdir -p "$INSTALL_DIR"   # dev 的使用者層級目錄可能不存在

    # 原子式換裝＋保留一版：先裝 .new、現版移到 .prev（rollback 用）、再換上 .new。
    # 中途失敗不會留下「沒有輸入法」的空窗；.prev 只留最近一版。
    $SUDO cp -R "$IM_APP" "$INSTALL_DIR/$IM_APP_NAME.app.new"
    $SUDO rm -rf "$INSTALL_DIR/$IM_APP_NAME.app.prev"
    [ -d "$INSTALL_DIR/$IM_APP_NAME.app" ] && $SUDO mv "$INSTALL_DIR/$IM_APP_NAME.app" "$INSTALL_DIR/$IM_APP_NAME.app.prev"
    $SUDO mv "$INSTALL_DIR/$IM_APP_NAME.app.new" "$INSTALL_DIR/$IM_APP_NAME.app"
    $SUDO chmod -R a+rX "$INSTALL_DIR/$IM_APP_NAME.app"
    # macOS 27 要求簽章 Identifier 與 Info.plist Bundle ID 一致，否則 IMK 拒絕 XPC endpoint（issue #16）：
    # 不帶 --identifier 時曾出現 Identifier=YabomishIM（與 Bundle ID 不一致），導致「看得到圖示、無法輸入」。
    $SUDO codesign -s - --force --deep --identifier "$IM_BUNDLE_ID" "$INSTALL_DIR/$IM_APP_NAME.app" 2>/dev/null || true
    local GOT_ID; GOT_ID=$(codesign -dv "$INSTALL_DIR/$IM_APP_NAME.app" 2>&1 | awk -F= '/^Identifier=/{print $2}')
    [ "$GOT_ID" = "$IM_BUNDLE_ID" ] || warn "簽章 Identifier 異常（$GOT_ID），macOS 27 可能無法輸入；見 issue #16"

    # 字表
    mkdir -p "$USER_DIR/tables"
    # emoji.txt no longer deployed — emoji handled by emoji_char_map.json suggestion system
    [ -f "$ROOT/liu.cin" ] && [ ! -f "$USER_DIR/liu.cin" ] && cp "$ROOT/liu.cin" "$USER_DIR/"

    # 自訂指令：部署 capture script + 預設 commands.json
    cp "$IM_RES/yabomish_capture.sh" "$USER_DIR/" && chmod +x "$USER_DIR/yabomish_capture.sh"
    [ ! -f "$USER_DIR/commands.json" ] && cp "$IM_RES/commands-example.json" "$USER_DIR/commands.json"

    ok "輸入法已安裝"
    [ -f "$USER_DIR/liu.cin" ] || [ -f "$USER_DIR/liu.bin" ] && ok "字表就緒" || warn "尚未偵測到字表，首次切換時會引導匯入"
    [ -d "$INSTALL_DIR/$IM_APP_NAME.app.prev" ] && ok "上一版已保留為 .prev（rollback 可還原）"

    restart_im
}

restart_im() {
    printf "${C}> 重新啟動輸入法...${N}\n"
    killall "$IM_APP_NAME" 2>/dev/null || true
    sleep 1

    # Force the system to re-scan input sources (imklaunchagent is blocked by
    # Launch Constraint Violation on macOS 26+ — kills TextInputMenuAgent instead)
    killall TextInputMenuAgent 2>/dev/null || true

    # 覆蓋安裝不會自動重掃 bundle：舊註冊快取會讓新 plist/icon 失效，
    # 輸入法選單消失或輪替跳過。顯式 TISRegisterInputSource（tools/register_im）。
    if [ ! -x "$ROOT/tools/register_im" ]; then
        clang -framework Carbon -framework Foundation "$ROOT/tools/register_im.m" -o "$ROOT/tools/register_im" 2>/dev/null || true
    fi
    [ -x "$ROOT/tools/register_im" ] && "$ROOT/tools/register_im" "$INSTALL_DIR/$IM_APP_NAME.app" || true

    # Try launching directly
    open "$INSTALL_DIR/$IM_APP_NAME.app" 2>/dev/null || true
    sleep 2

    if pgrep -q "$IM_APP_NAME"; then
        ok "輸入法已啟動"
        ok "到 系統設定 → 鍵盤 → 輸入方式 → + → 繁體中文 → $IM_APP_NAME"
    else
        warn "系統未自動啟動，請登出再登入"
    fi
}

# 還原上一版：install 保留的 .prev 與現版互換（rollback 本身可逆）。
do_rollback() {
    local CUR="$INSTALL_DIR/$IM_APP_NAME.app"
    local PREV="$INSTALL_DIR/$IM_APP_NAME.app.prev"
    [ -d "$PREV" ] || err "沒有可還原的上一版（$PREV 不存在）"
    [ -n "$SUDO" ] && sudo -v
    printf "${C}> 還原上一版 $IM_APP_NAME...${N}\n"
    killall "$IM_APP_NAME" 2>/dev/null || true; sleep 1
    [ -d "$CUR" ] && $SUDO mv "$CUR" "$INSTALL_DIR/$IM_APP_NAME.app.rollback-tmp"
    $SUDO mv "$PREV" "$CUR"
    [ -d "$INSTALL_DIR/$IM_APP_NAME.app.rollback-tmp" ] && \
        $SUDO mv "$INSTALL_DIR/$IM_APP_NAME.app.rollback-tmp" "$PREV"
    $SUDO chmod -R a+rX "$CUR"
    ok "已還原上一版（現版降為 .prev）"
    restart_im
}

install_prefs() {
    if [ "${YABOMISH_DEV:-0}" = "1" ]; then
        # dev 變體：~/Applications 下產生自給自足的偏好設定 app——
        # 內嵌本輪 build 的 Prefs binary 與資源，launch script 以
        # -prefsSuite $IM_BUNDLE_ID 啟動（user-level 免 sudo，
        # 不依賴 /Applications 的 stable 版本）。
        [ ! -d "$PREFS_APP" ] && err "請先選 1 或 2 編譯"
        local WAPP="$HOME/Applications/${IM_APP_NAME}Prefs.app"
        rm -rf "$WAPP"
        mkdir -p "$WAPP/Contents/MacOS" "$WAPP/Contents/Resources"
        cp "$PREFS_APP/Contents/MacOS/YabomishPrefs" "$WAPP/Contents/MacOS/"
        cp -R "$PREFS_APP/Contents/Resources" "$WAPP/Contents/" 2>/dev/null || true
        cat > "$WAPP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key><string>${IM_BUNDLE_ID}.prefs</string>
	<key>CFBundleName</key><string>${IM_APP_NAME}Prefs</string>
	<key>CFBundleDisplayName</key><string>${IM_APP_NAME} 偏好設定</string>
	<key>CFBundleExecutable</key><string>launch</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleIconFile</key><string>AppIconDev</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
</dict>
</plist>
EOF
        # 關於頁要顯示版號：從本輪 build 的 plist 帶過來（wrapper plist 沒有會顯示 "?"）
        local PVER PBLD
        PVER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PREFS_APP/Contents/Info.plist" 2>/dev/null || true)
        PBLD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PREFS_APP/Contents/Info.plist" 2>/dev/null || true)
        [ -n "$PVER" ] && /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $PVER" "$WAPP/Contents/Info.plist"
        [ -n "$PBLD" ] && /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $PBLD" "$WAPP/Contents/Info.plist"
        cat > "$WAPP/Contents/MacOS/launch" <<EOF
#!/bin/bash
cd "\$(dirname "\$0")" && exec ./YabomishPrefs -prefsSuite $IM_BUNDLE_ID
EOF
        chmod +x "$WAPP/Contents/MacOS/launch" "$WAPP/Contents/MacOS/YabomishPrefs"
        ok "偏好設定 app -> ~/Applications/${IM_APP_NAME}Prefs.app（點開即 dev suite）"
        return 0
    fi
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
        printf "確定要移除 $IM_APP_NAME？[y/N] "; read -r c || c=""
        [[ "$c" =~ ^[Yy]$ ]] || { echo "已取消。"; return 0; }
    fi
    killall "$IM_APP_NAME" 2>/dev/null || true
    [ "${YABOMISH_DEV:-0}" != "1" ] && killall YabomishPrefs 2>/dev/null || true
    sleep 0.5
    $SUDO rm -rf "$INSTALL_DIR/$IM_APP_NAME.app"
    $SUDO rm -rf "$INSTALL_DIR/$IM_APP_NAME.app.prev"
    $SUDO rm -rf "$INSTALL_DIR/$IM_APP_NAME.app.new"
    if [ "${YABOMISH_DEV:-0}" != "1" ]; then
        $SUDO rm -rf "$HOME/Library/Input Methods/$IM_APP_NAME.app"   # all_platforms.sh 裝在使用者層級的副本
        $SUDO rm -rf /Applications/YabomishPrefs.app
    else
        rm -rf "$HOME/Applications/${IM_APP_NAME}Prefs.app"   # dev prefs wrapper
    fi
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
    printf "  ${B}6)${N} 還原上一版（rollback）\n"
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
      ./yabomish.sh rollback              還原上一版（與 .prev 互換，可再換回）
      ./yabomish.sh uninstall [--yes]     移除（--yes 跳過所有確認，連使用者資料一起刪）
      ./yabomish.sh test                  執行測試（YabomishIM/Tests/run_tests.sh）
      YABOMISH_DEV=1 ./yabomish.sh build  編譯實驗變體 YabomishDev（獨立 bundle ID/資料目錄，
                                        與 stable 並存；install/uninstall 同樣加 YABOMISH_DEV=1）
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
    rollback)
        [ $# -eq 1 ] || { usage; exit 2; }
        do_rollback
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
        6) menu_run do_rollback;;
        t|T) menu_run bash "$ROOT/YabomishIM/Tests/run_tests.sh";;
        0) echo "Bye!"; exit 0;;
        *) warn "請輸入 0-6 或 T";;
    esac
done
