#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Developer ID Application certificate (set via env or defaults)
: "${DEVELOPER_ID:=Developer ID Application: CHIH HSIAN LIN (2SYA986D7H)}"

# Notarization credentials (one of these groups required to notarize)
# 1. NOTARY_PROFILE (keychain profile stored via `xcrun notarytool store-credentials`)
# 2. APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD + APPLE_TEAM_ID
# 3. ASC_PRIVATE_KEY (path or content) + ASC_KEY_ID + ASC_ISSUER_ID

VER=$(grep '^## \[' "$ROOT/CHANGELOG.md" | grep -v '\[Unreleased\]' | head -1 | sed 's/.*\[\(.*\)\].*/\1/')
HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
STAMP=$(date +%Y%m%d.%H%M)
IM_BUILD="$ROOT/YabomishIM/build"
IM_APP="$IM_BUILD/YabomishIM.app"
PREFS_DIR="$ROOT/YabomishPrefs"
PREFS_APP="$PREFS_DIR/YabomishPrefs.app"
INSTALLER_APP="$ROOT/build/安裝 Yabomish.app"

ok()   { printf "\033[32m[OK] %s\033[0m\n" "$1"; }
info() { printf "\033[36m[>] %s\033[0m\n" "$1"; }
err()  { printf "\033[31m[ERR] %s\033[0m\n" "$1"; exit 1; }

check_xcode() {
    xcode-select -p &>/dev/null || err "Xcode Command Line Tools required"
}

# Modes: dl（網路版，預設：完整程式碼、不含語料，首次啟動自 GitHub Releases 下載）
#        lite（內含基礎語料）／full（全打包）／min（極簡，無聯想）
build_im() {
    local mode="${1:-dl}"
    info "Building YabomishIM ($mode)..."
    rm -rf "$IM_BUILD"
    mkdir -p "$IM_APP/Contents/MacOS" "$IM_APP/Contents/Resources"

    cp "$ROOT/YabomishIM/Resources/Info.plist" "$IM_APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" "$IM_APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VER}.${STAMP}.${HASH}" "$IM_APP/Contents/Info.plist"

    # Core resources
    for f in icon.tiff icon.icns icon_right.tiff icon_left.tiff \
             zhuyin_data.json pinyin_data.json t2s.json s2t.json \
             char_freq.json corpus_manifest.json; do
        [ -f "$ROOT/YabomishIM/Resources/$f" ] && cp "$ROOT/YabomishIM/Resources/$f" "$IM_APP/Contents/Resources/"
    done
    [ -d "$ROOT/YabomishIM/Resources/tables" ] && cp -R "$ROOT/YabomishIM/Resources/tables" "$IM_APP/Contents/Resources/"
    [ -d "$ROOT/YabomishIM/Resources/Plugins" ] && cp -R "$ROOT/YabomishIM/Resources/Plugins" "$IM_APP/Contents/Resources/"

    # 基礎語料（極簡版與網路版不含；網路版首次啟動由 DataDownloader 依
    # corpus_manifest.json 自 GitHub Releases 下載並解壓至 Application Support，
    # WikiCorpus.resolvePath 優先讀 Application Support，下載後即生效）
    if [ "$mode" != "min" ] && [ "$mode" != "dl" ]; then
        for f in emoji_char_map.json bigram.bin trigram.bin word_ngram.bin word_news.bin chengyu.bin \
                 phrases.bin ner_phrases.bin yoji.bin region_tw.txt region_cn.txt; do
            [ -f "$ROOT/YabomishIM/Resources/$f" ] && cp "$ROOT/YabomishIM/Resources/$f" "$IM_APP/Contents/Resources/"
        done
    fi


    # Professional dictionaries
    if [ "$mode" = "full" ]; then
        for f in "$ROOT/YabomishIM/Resources"/terms_*.bin; do
            [ -f "$f" ] && cp "$f" "$IM_APP/Contents/Resources/"
        done
    fi

    local flags=""
    if [ "$mode" = "min" ]; then flags="-DMINIMAL"; fi

    swiftc -module-name YabomishIM \
        -target arm64-apple-macos14.0 \
        -sdk "$(xcrun --show-sdk-path)" -O $flags \
        -o "$IM_APP/Contents/MacOS/YabomishIM" \
        $(find "$ROOT/YabomishIM/Sources" -name "*.swift" | sort)
    ok "YabomishIM.app [$mode] build ${STAMP}.${HASH}"
}

build_prefs() {
    info "Building YabomishPrefs..."
    rm -rf "$PREFS_APP"
    mkdir -p "$PREFS_APP/Contents/MacOS" "$PREFS_APP/Contents/Resources"

    cp "$PREFS_DIR/Resources/Info.plist" "$PREFS_APP/Contents/Info.plist"
    cp "$PREFS_DIR/Resources/AppIcon.icns" "$PREFS_APP/Contents/Resources/"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" "$PREFS_APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VER}.${STAMP}.${HASH}" "$PREFS_APP/Contents/Info.plist"

    swiftc -module-name YabomishPrefs \
        -target arm64-apple-macos14.0 \
        -sdk "$(xcrun --show-sdk-path)" -O \
        -framework SwiftUI -framework AppKit -framework UniformTypeIdentifiers \
        -o "$PREFS_APP/Contents/MacOS/YabomishPrefs" \
        "$PREFS_DIR"/Sources/*.swift

    chmod +x "$PREFS_APP/Contents/MacOS/YabomishPrefs"
    ok "YabomishPrefs.app"
}

sign_apps() {
    info "Signing with: $DEVELOPER_ID"
    codesign --force --deep --sign "$DEVELOPER_ID" \
        --entitlements "$ROOT/tools/YabomishIM.entitlements" \
        --options runtime --timestamp \
        "$IM_APP"
    codesign --force --deep --sign "$DEVELOPER_ID" \
        --options runtime --timestamp \
        "$PREFS_APP"
    codesign --verify --deep --strict --verbose=2 "$IM_APP"
    codesign --verify --deep --strict --verbose=2 "$PREFS_APP"
    ok "Apps signed and verified"
}

create_installer() {
    local variant="${1:-lite}"
    info "Building installer app ($variant)..."
    local APP="$INSTALLER_APP"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

    cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>安裝 Yabomish</string>
    <key>CFBundleDisplayName</key><string>安裝 Yabomish</string>
    <key>CFBundleIdentifier</key><string>com.yabomishim.inputmethod.YabomishInstaller</string>
    <key>CFBundleExecutable</key><string>install</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VER</string>
    <key>CFBundleVersion</key><string>$VER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
    echo -n "APPL????" > "$APP/Contents/PkgInfo"

    cp -R "$IM_APP" "$APP/Contents/Resources/"
    cp -R "$PREFS_APP" "$APP/Contents/Resources/"
    [ -f "$ROOT/YabomishIM/Resources/yabomish_capture.sh" ] && cp "$ROOT/YabomishIM/Resources/yabomish_capture.sh" "$APP/Contents/Resources/"
    [ -f "$ROOT/YabomishIM/Resources/commands-example.json" ] && cp "$ROOT/YabomishIM/Resources/commands-example.json" "$APP/Contents/Resources/"

    cat > "$APP/Contents/Resources/root_install.sh" <<'EOF'
#!/bin/bash
set -e
IM_SRC="$1"; PREFS_SRC="$2"; ICON="$3"; LBL="$4"
APP="/Library/Input Methods/YabomishIM.app"
killall YabomishIM 2>/dev/null || true; sleep 1
rm -rf "$APP"
cp -R "$IM_SRC" "/Library/Input Methods/"
chmod -R a+rX "$APP"
DIR="$APP/Contents/Resources"
[ "$ICON" = "right" ] && [ -f "$DIR/icon_right.tiff" ] && cp "$DIR/icon_right.tiff" "$DIR/icon.tiff"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $LBL" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $LBL" "$PLIST"
rm -rf "/Applications/YabomishPrefs.app"
cp -R "$PREFS_SRC" "/Applications/"
chmod -R a+rX "/Applications/YabomishPrefs.app"
EOF
    chmod +x "$APP/Contents/Resources/root_install.sh"

    cat > "$APP/Contents/MacOS/install" <<'EOF'
#!/bin/bash
set -e
RES="$(cd "$(dirname "$0")/../Resources" && pwd)"
IM_SRC="$RES/YabomishIM.app"
PREFS_SRC="$RES/YabomishPrefs.app"
VARIANT="__BAKED_VARIANT__"

ICON=$(defaults read com.yabomishim.inputmethod.YabomishIM iconDirection 2>/dev/null || echo left)
RAW=$(defaults read com.yabomishim.inputmethod.YabomishIM switchDisplay 2>/dev/null || echo "繁中")
case "$RAW" in
    yabo)          LBL="Yabo";;
    yabomish|Yabo) LBL="Yabomish";;
    繁中)          LBL="繁中";;
    🦐)            LBL="🦐";;
    *)             LBL="繁中";;
esac

SYS_LANG=$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2s/[[:space:]"]*\([^,)]*\).*/\1/p')
case "$SYS_LANG" in
    zh-Hans*|zh-CN*|zh_SG*)
        L_DONE="安装完成。"; L_STEP="最后一步：到「系统设置 → 键盘 → 输入方式」按 + 添加 Yabomish。"; L_BTN="打开键盘设置"; L_CANCEL="已取消安装。"
        [ "$VARIANT" = "full" ] && L_NOTE="首次打字时会自动从 GitHub 下载全量语料＋专业词典（约100MB）。" || L_NOTE="首次打字时会自动从 GitHub 下载联想语料（约15MB）。";;
    zh*)
        L_DONE="安裝完成。"; L_STEP="最後一步：到「系統設定 → 鍵盤 → 輸入方式」按 + 加入 Yabomish。"; L_BTN="打開鍵盤設定"; L_CANCEL="已取消安裝。"
        [ "$VARIANT" = "full" ] && L_NOTE="首次打字時會自動從 GitHub 下載全量語料＋專業詞典（約100MB）。" || L_NOTE="首次打字時會自動從 GitHub 下載聯想語料（約15MB）。";;
    *)
        L_DONE="Installation complete."; L_STEP="Final step: System Settings → Keyboard → Input Sources, press + to add Yabomish."; L_BTN="Open Keyboard Settings"; L_CANCEL="Installation cancelled."
        [ "$VARIANT" = "full" ] && L_NOTE="The full corpus and 36 domain dictionaries (~100MB) download automatically on first use." || L_NOTE="The suggestion corpus (~15MB) downloads automatically on first use.";;
esac

if ! osascript -e "do shell script \"bash '$RES/root_install.sh' '$IM_SRC' '$PREFS_SRC' '$ICON' '$LBL'\" with administrator privileges with prompt \"Yabomish\""; then
    osascript -e "display dialog \"$L_CANCEL\" buttons {\"OK\"} default button 1 with title \"Yabomish\"" || true
    exit 0
fi

UD="$HOME/Library/Application Support/Yabomish"
mkdir -p "$UD/tables"
[ -f "$RES/yabomish_capture.sh" ] && cp "$RES/yabomish_capture.sh" "$UD/" && chmod +x "$UD/yabomish_capture.sh"
[ ! -f "$UD/commands.json" ] && [ -f "$RES/commands-example.json" ] && cp "$RES/commands-example.json" "$UD/commands.json"

defaults write com.yabomishim.inputmethod.YabomishIM corpusVariant "$VARIANT"

killall YabomishIM 2>/dev/null || true; sleep 1
[ -x /System/Library/Frameworks/InputMethodKit.framework/Versions/A/Resources/imklaunchagent ] && /System/Library/Frameworks/InputMethodKit.framework/Versions/A/Resources/imklaunchagent 2>/dev/null || true
open "/Library/Input Methods/YabomishIM.app" 2>/dev/null || true

osascript -e "display dialog \"$L_DONE\n\n$L_STEP\n\n$L_NOTE\" buttons {\"$L_BTN\"} default button 1 with title \"Yabomish\"" || true
open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?InputSources" 2>/dev/null || true
EOF
    sed -i '' "s/__BAKED_VARIANT__/$variant/" "$APP/Contents/MacOS/install"
    chmod +x "$APP/Contents/MacOS/install"

    codesign --force --deep --sign "$DEVELOPER_ID" \
        --options runtime --timestamp "$APP"
    codesign --verify --deep --strict "$APP"
    ok "安裝 Yabomish.app ($variant)"
}

create_dmg() {
    local variant="${1:-lite}"
    local DMG_NAME="$ROOT/Yabomish-精簡.dmg"
    [ "$variant" = "full" ] && DMG_NAME="$ROOT/Yabomish-全量.dmg"
    info "Creating $(basename "$DMG_NAME")..."
    rm -rf "$ROOT/build/dmg_staging"
    mkdir -p "$ROOT/build/dmg_staging"
    cp -R "$INSTALLER_APP" "$ROOT/build/dmg_staging/"
    if [ "$variant" = "full" ]; then
        cat > "$ROOT/build/dmg_staging/README.txt" <<'EOF'
Yabomish 安裝說明（全量版）
==========================
1. 雙擊「安裝 Yabomish.app」，輸入管理員密碼
   （輸入法 → /Library/Input Methods；偏好設定 → /Applications）
2. 安裝完成會自動開啟「輸入方式」列表：按 + 加入 Yabomish
3. 首次打字時自動從 GitHub 下載全量語料＋28 部專業詞典（約 100MB，
   SHA-256 驗證後存於 ~/Library/Application Support/Yabomish/）
離線時打字、查碼、繁簡轉換不受影響，僅聯想功能等語料就緒後生效。

macOS 14.0+ (Apple Silicon) 適用。
EOF
    else
        cat > "$ROOT/build/dmg_staging/README.txt" <<'EOF'
Yabomish 安裝說明（精簡版）
==========================
1. 雙擊「安裝 Yabomish.app」，輸入管理員密碼
   （輸入法 → /Library/Input Methods；偏好設定 → /Applications）
2. 安裝完成會自動開啟「輸入方式」列表：按 + 加入 Yabomish
3. 首次打字時自動從 GitHub 下載聯想語料（約 15MB，
   SHA-256 驗證後存於 ~/Library/Application Support/Yabomish/）
離線時打字、查碼、繁簡轉換不受影響，僅聯想功能等語料就緒後生效。
需要 28 部專業詞典請改用「全量版」。

macOS 14.0+ (Apple Silicon) 適用。
EOF
    fi

    local rw_dmg="$ROOT/Yabomish_rw.dmg"
    rm -f "$rw_dmg" "$DMG_NAME"
    hdiutil create -srcfolder "$ROOT/build/dmg_staging" \
        -volname "Yabomish" \
        -fs HFS+J \
        -format UDRW \
        -size 200m \
        "$rw_dmg"
    hdiutil convert "$rw_dmg" -format UDZO -o "$DMG_NAME"
    rm -f "$rw_dmg"
    ok "DMG: $DMG_NAME"
}

create_pkg() {
    local variant="${1:-lite}"
    local PKG_OUT="$ROOT/Yabomish-精簡.pkg"
    [ "$variant" = "full" ] && PKG_OUT="$ROOT/Yabomish-全量.pkg"
    make_one_pkg "$variant" "$PKG_OUT"
}

make_one_pkg() {
    local variant="$1" pkg_out="$2"
    info "Building $(basename "$pkg_out")..."
    local STAGE="$ROOT/build/pkg_stage"
    rm -rf "$STAGE"
    mkdir -p "$STAGE/payload/Library/Input Methods" "$STAGE/payload/Applications" \
             "$STAGE/scripts" "$STAGE/res/en.lproj" "$STAGE/res/zh_TW.lproj" "$STAGE/res/zh_CN.lproj"
    cp -R "$IM_APP" "$STAGE/payload/Library/Input Methods/"
    cp -R "$PREFS_APP" "$STAGE/payload/Applications/"
    [ -f "$ROOT/YabomishIM/Resources/yabomish_capture.sh" ] && cp "$ROOT/YabomishIM/Resources/yabomish_capture.sh" "$STAGE/scripts/"
    [ -f "$ROOT/YabomishIM/Resources/commands-example.json" ] && cp "$ROOT/YabomishIM/Resources/commands-example.json" "$STAGE/scripts/"

    cat > "$STAGE/scripts/postinstall" <<'EOF'
#!/bin/bash
set -e
CONSOLE_USER=$(stat -f%Su /dev/console)
CONSOLE_UID=$(stat -f%u /dev/console)
CONSOLE_HOME=$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory | awk '{print $2}')

killall YabomishIM 2>/dev/null || true; sleep 1

ICON=$(/usr/bin/sudo -u "$CONSOLE_USER" defaults read com.yabomishim.inputmethod.YabomishIM iconDirection 2>/dev/null || echo left)
RAW=$(/usr/bin/sudo -u "$CONSOLE_USER" defaults read com.yabomishim.inputmethod.YabomishIM switchDisplay 2>/dev/null || echo "繁中")
case "$RAW" in
    yabo)          LBL="Yabo";;
    yabomish|Yabo) LBL="Yabomish";;
    繁中)          LBL="繁中";;
    🦐)            LBL="🦐";;
    *)             LBL="繁中";;
esac
DIR="/Library/Input Methods/YabomishIM.app/Contents/Resources"
[ "$ICON" = "right" ] && [ -f "$DIR/icon_right.tiff" ] && cp "$DIR/icon_right.tiff" "$DIR/icon.tiff"
PLIST="/Library/Input Methods/YabomishIM.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $LBL" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $LBL" "$PLIST"

/usr/bin/sudo -u "$CONSOLE_USER" defaults write com.yabomishim.inputmethod.YabomishIM corpusVariant "__BAKED_VARIANT__"

UD="$CONSOLE_HOME/Library/Application Support/Yabomish"
mkdir -p "$UD/tables"
if [ -f "$SCRIPT_DIR/yabomish_capture.sh" ]; then
    cp "$SCRIPT_DIR/yabomish_capture.sh" "$UD/"
    chown "$CONSOLE_USER" "$UD/yabomish_capture.sh"; chmod +x "$UD/yabomish_capture.sh"
fi
if [ ! -f "$UD/commands.json" ] && [ -f "$SCRIPT_DIR/commands-example.json" ]; then
    cp "$SCRIPT_DIR/commands-example.json" "$UD/commands.json"
    chown "$CONSOLE_USER" "$UD/commands.json"
fi

[ -x /System/Library/Frameworks/InputMethodKit.framework/Versions/A/Resources/imklaunchagent ] && /System/Library/Frameworks/InputMethodKit.framework/Versions/A/Resources/imklaunchagent 2>/dev/null || true
launchctl asuser "$CONSOLE_UID" /usr/bin/open "/Library/Input Methods/YabomishIM.app" 2>/dev/null || true
launchctl asuser "$CONSOLE_UID" /usr/bin/open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?InputSources" 2>/dev/null || true

exit 0
EOF
    sed -i '' "s/__BAKED_VARIANT__/$variant/" "$STAGE/scripts/postinstall"
    chmod +x "$STAGE/scripts/postinstall"

    local WELCOME_NOTE="網路版：首次打字時自動從 GitHub 下載聯想語料（約 15MB）；離線時打字、查碼、繁簡轉換不受影響。"
    [ "$variant" = "full" ] && WELCOME_NOTE="全量版：首次打字時自動從 GitHub 下載全量語料＋28 部專業詞典（約 100MB）。"

    cat > "$STAGE/res/zh_TW.lproj/welcome.html" <<EOF
<!DOCTYPE html><html><head><meta charset="utf-8"><style>body{font-family:-apple-system,"PingFang TC";font-size:13px;line-height:1.6}</style></head>
<body><h1>Yabomish 安裝</h1>
<p>將安裝：</p><ul>
<li>輸入法 → <code>/Library/Input Methods</code></li>
<li>偏好設定 → <code>/Applications</code></li></ul>
<p>安裝後請到「系統設定 → 鍵盤 → 輸入方式」按 <b>+</b> 加入 <b>Yabomish</b>（繁體中文）。</p>
<p>$WELCOME_NOTE</p>
</body></html>
EOF
    cat > "$STAGE/res/zh_CN.lproj/welcome.html" <<EOF
<!DOCTYPE html><html><head><meta charset="utf-8"><style>body{font-family:-apple-system,"PingFang SC";font-size:13px;line-height:1.6}</style></head>
<body><h1>Yabomish 安装</h1>
<p>将安装：</p><ul>
<li>输入法 → <code>/Library/Input Methods</code></li>
<li>偏好设置 → <code>/Applications</code></li></ul>
<p>安装后请到「系统设置 → 键盘 → 输入方式」按 <b>+</b> 添加 <b>Yabomish</b>（繁体中文）。</p>
<p>$WELCOME_NOTE</p>
</body></html>
EOF
    cat > "$STAGE/res/en.lproj/welcome.html" <<EOF
<!DOCTYPE html><html><head><meta charset="utf-8"><style>body{font-family:-apple-system;font-size:13px;line-height:1.6}</style></head>
<body><h1>Install Yabomish</h1>
<p>Installs:</p><ul>
<li>Input method → <code>/Library/Input Methods</code></li>
<li>Preferences → <code>/Applications</code></li></ul>
<p>After installing, add Yabomish in System Settings → Keyboard → Input Sources (Traditional Chinese).</p>
<p>$([ "$variant" = "full" ] && echo "Full build: full corpus plus 36 domain dictionaries (~100MB) download from GitHub on first use." || echo "Online build: suggestion corpus (~15MB) is downloaded from GitHub on first use.")</p>
</body></html>
EOF
    cat > "$STAGE/res/zh_TW.lproj/conclusion.html" <<'EOF'
<!DOCTYPE html><html><head><meta charset="utf-8"><style>body{font-family:-apple-system,"PingFang TC";font-size:13px;line-height:1.6}</style></head>
<body><h2>安裝完成</h2>
<p>最後一步：到「系統設定 → 鍵盤 → 輸入方式」按 <b>+</b> 加入 <b>Yabomish</b>（繁體中文）。輸入方式列表已為你自動開啟。</p>
</body></html>
EOF
    cat > "$STAGE/res/zh_CN.lproj/conclusion.html" <<'EOF'
<!DOCTYPE html><html><head><meta charset="utf-8"><style>body{font-family:-apple-system,"PingFang SC";font-size:13px;line-height:1.6}</style></head>
<body><h2>安装完成</h2>
<p>最后一步：到「系统设置 → 键盘 → 输入方式」按 <b>+</b> 添加 <b>Yabomish</b>（繁体中文）。输入方式列表已为你自动开启。</p>
</body></html>
EOF
    cat > "$STAGE/res/en.lproj/conclusion.html" <<'EOF'
<!DOCTYPE html><html><head><meta charset="utf-8"><style>body{font-family:-apple-system;font-size:13px;line-height:1.6}</style></head>
<body><h2>Installation Complete</h2>
<p>Final step: add Yabomish in System Settings → Keyboard → Input Sources (Traditional Chinese). The Input Sources list has been opened for you.</p>
</body></html>
EOF

    local COMP="$STAGE/Yabomish-component.pkg"
    pkgbuild --root "$STAGE/payload" \
             --scripts "$STAGE/scripts" \
             --identifier com.yabomishim.inputmethod.YabomishIM \
             --version "$VER" \
             --install-location / \
             "$COMP"

    local GEN="$STAGE/gen.pkg"
    productbuild --package "$COMP" "$GEN"
    local FLAT="$STAGE/flat"
    pkgutil --expand "$GEN" "$FLAT"
    python3 - "$FLAT/Distribution" <<'PYINNER'
import sys
p = sys.argv[1]
s = open(p).read()
inject = ('    <title>Yabomish</title>\n'
          '    <welcome file="welcome.html"/>\n'
          '    <conclusion file="conclusion.html"/>\n')
anchor = '<installer-gui-script minSpecVersion="1">'
assert anchor in s, "Distribution.xml anchor not found"
s = s.replace(anchor, anchor + "\n" + inject, 1)
open(p, "w").write(s)
PYINNER

    if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Installer"; then
        local PKG_IDENTITY
        PKG_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Installer" | head -1 | sed 's/^.*"\(.*\)".*/\1/')
        info "Signing pkg with: $PKG_IDENTITY"
        productbuild --distribution "$FLAT/Distribution" --resources "$STAGE/res" \
                     --package-path "$STAGE" --sign "$PKG_IDENTITY" "$pkg_out"
    else
        info "找不到 Developer ID Installer 憑證，產出未簽署 pkg（僅供本機測試；散佈前需簽署＋公證）"
        productbuild --distribution "$FLAT/Distribution" --resources "$STAGE/res" \
                     --package-path "$STAGE" "$pkg_out"
    fi
    rm -rf "$STAGE"
    ok "Yabomish pkg ($(basename "$pkg_out"))"
}

notarize() {
    local variant="${1:-lite}"
    local DMG_NAME="$ROOT/Yabomish-精簡.dmg"
    [ "$variant" = "full" ] && DMG_NAME="$ROOT/Yabomish-全量.dmg"
    local PKG_OUT="$ROOT/Yabomish-精簡.pkg"
    [ "$variant" = "full" ] && PKG_OUT="$ROOT/Yabomish-全量.pkg"

    local args=()
    if [ -n "$NOTARY_PROFILE" ]; then
        args+=(--keychain-profile "$NOTARY_PROFILE")
    elif [ -n "$APPLE_ID" ] && [ -n "$APPLE_APP_SPECIFIC_PASSWORD" ] && [ -n "$APPLE_TEAM_ID" ]; then
        args+=(--apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID")
    elif [ -n "$ASC_PRIVATE_KEY" ] && [ -n "$ASC_KEY_ID" ] && [ -n "$ASC_ISSUER_ID" ]; then
        if [ -f "$ASC_PRIVATE_KEY" ]; then
            args+=(--key "$ASC_PRIVATE_KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
        else
            local tmp_key="$ROOT/build/asc_key.p8"
            mkdir -p "$ROOT/build"
            printf '%s\n' "$ASC_PRIVATE_KEY" > "$tmp_key"
            args+=(--key "$tmp_key" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
        fi
    else
        info "No notarization credentials found. Skipping notarization."
        info "Set one of:"
        info "  NOTARY_PROFILE"
        info "  APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD + APPLE_TEAM_ID"
        info "  ASC_PRIVATE_KEY + ASC_KEY_ID + ASC_ISSUER_ID"
        return 0
    fi

    info "Submitting $(basename "$DMG_NAME") to Apple notary service..."
    xcrun notarytool submit "$DMG_NAME" "${args[@]}" --wait
    info "Stapling $(basename "$DMG_NAME")..."
    xcrun notarytool staple "$DMG_NAME"
    ok "Notarization complete: $DMG_NAME"

    if [ -f "$PKG_OUT" ]; then
        info "Submitting $(basename "$PKG_OUT") to Apple notary service..."
        xcrun notarytool submit "$PKG_OUT" "${args[@]}" --wait
        xcrun notarytool staple "$PKG_OUT"
        ok "Notarization complete: $PKG_OUT"
    fi
}

main() {
    check_xcode
    # 兩包制：精簡（基礎語料）／全量（全量語料＋專業詞典）。極簡版走 yabomish.sh。
    local variant="${1:-lite}"
    case "$variant" in full) ;; *) variant="lite";; esac
    build_im dl
    build_prefs
    create_installer "$variant"
    sign_apps
    create_dmg "$variant"
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Installer"; then
        create_pkg "$variant"
    elif [ "${WITH_PKG:-0}" = "1" ]; then
        info "WITH_PKG=1：產出未簽署 pkg（本機測試用）"
        create_pkg "$variant"
    else
        info "略過 pkg（無 Developer ID Installer 憑證；WITH_PKG=1 可強制產出）——DMG 為唯一散佈物"
    fi
    notarize "$variant"
}

main "$@"
