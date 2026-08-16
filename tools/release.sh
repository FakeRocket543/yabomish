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

VER=$(grep -m1 '^## \[' "$ROOT/CHANGELOG.md" | sed 's/.*\[\(.*\)\].*/\1/')
HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
STAMP=$(date +%Y%m%d.%H%M)
IM_BUILD="$ROOT/YabomishIM/build"
IM_APP="$IM_BUILD/YabomishIM.app"
PREFS_DIR="$ROOT/YabomishPrefs"
PREFS_APP="$PREFS_DIR/YabomishPrefs.app"
DMG_NAME="Yabomish.dmg"

ok()   { printf "\033[32m[OK] %s\033[0m\n" "$1"; }
info() { printf "\033[36m[>] %s\033[0m\n" "$1"; }
err()  { printf "\033[31m[ERR] %s\033[0m\n" "$1"; exit 1; }

check_xcode() {
    xcode-select -p &>/dev/null || err "Xcode Command Line Tools required"
}

build_im() {
    local mode="${1:-full}"
    info "Building YabomishIM ($mode)..."
    rm -rf "$IM_BUILD"
    mkdir -p "$IM_APP/Contents/MacOS" "$IM_APP/Contents/Resources"

    cp "$ROOT/YabomishIM/Resources/Info.plist" "$IM_APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" "$IM_APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VER}.${STAMP}.${HASH}" "$IM_APP/Contents/Info.plist"

    # Core resources
    for f in icon.tiff icon.icns icon_right.tiff icon_left.tiff \
             zhuyin_data.json pinyin_data.json t2s.json s2t.json emoji_char_map.json \
             char_freq.json; do
        [ -f "$ROOT/YabomishIM/Resources/$f" ] && cp "$ROOT/YabomishIM/Resources/$f" "$IM_APP/Contents/Resources/"
    done
    [ -d "$ROOT/YabomishIM/Resources/tables" ] && cp -R "$ROOT/YabomishIM/Resources/tables" "$IM_APP/Contents/Resources/"

    # Base corpus
    for f in bigram.bin trigram.bin word_ngram.bin word_news.bin chengyu.bin \
             phrases.bin ner_phrases.bin yoji.bin region_tw.txt region_cn.txt; do
        [ -f "$ROOT/YabomishIM/Resources/$f" ] && cp "$ROOT/YabomishIM/Resources/$f" "$IM_APP/Contents/Resources/"
    done

    # Professional dictionaries
    if [ "$mode" = "full" ]; then
        for f in "$ROOT/YabomishIM/Resources"/terms_*.bin; do
            [ -f "$f" ] && cp "$f" "$IM_APP/Contents/Resources/"
        done
    fi

    echo -n "APPL????" > "$IM_APP/Contents/PkgInfo"

    swiftc -module-name YabomishIM \
        -target arm64-apple-macos14.0 \
        -sdk "$(xcrun --show-sdk-path)" -O \
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

create_dmg() {
    info "Creating $DMG_NAME..."
    rm -rf "$ROOT/build/dmg_staging"
    mkdir -p "$ROOT/build/dmg_staging"
    cp -R "$IM_APP" "$ROOT/build/dmg_staging/"
    cp -R "$PREFS_APP" "$ROOT/build/dmg_staging/"
    cat > "$ROOT/build/dmg_staging/README.txt" <<'EOF'
Yabomish 安裝說明
==================

1. 將 YabomishIM.app 拖曳到 /Library/Input Methods/（系統層級，需管理員密碼）
2. 將 YabomishPrefs.app 拖曳到 /Applications/
3. 開啟 YabomishPrefs，依照引導匯入 liu.cin 字表
4. 到「系統設定 → 鍵盤 → 輸入方式」加入「Yabomish」

macOS 14.0+ (Apple Silicon) 適用。
EOF

    local rw_dmg="$ROOT/Yabomish_rw.dmg"
    rm -f "$rw_dmg" "$ROOT/$DMG_NAME"
    hdiutil create -srcfolder "$ROOT/build/dmg_staging" \
        -volname "Yabomish" \
        -fs HFS+J \
        -format UDRW \
        -size 200m \
        "$rw_dmg"
    hdiutil convert "$rw_dmg" -format UDZO -o "$ROOT/$DMG_NAME"
    rm -f "$rw_dmg"
    ok "DMG: $ROOT/$DMG_NAME"
}

notarize() {
    local args=()
    if [ -n "$NOTARY_PROFILE" ]; then
        args+=(--keychain-profile "$NOTARY_PROFILE")
    elif [ -n "$APPLE_ID" ] && [ -n "$APPLE_APP_SPECIFIC_PASSWORD" ] && [ -n "$APPLE_TEAM_ID" ]; then
        args+=(--apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID")
    elif [ -n "$ASC_PRIVATE_KEY" ] && [ -n "$ASC_KEY_ID" ] && [ -n "$ASC_ISSUER_ID" ]; then
        if [ -f "$ASC_PRIVATE_KEY" ]; then
            args+=(--key "$ASC_PRIVATE_KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
        else
            # Write inline private key to a temp file
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

    info "Submitting $DMG_NAME to Apple notary service..."
    xcrun notarytool submit "$ROOT/$DMG_NAME" "${args[@]}" --wait

    info "Stapling $DMG_NAME..."
    xcrun notarytool staple "$ROOT/$DMG_NAME"
    ok "Notarization complete: $DMG_NAME"
}

main() {
    check_xcode
    local mode="${1:-full}"
    build_im "$mode"
    build_prefs
    sign_apps
    create_dmg
    notarize
}

main "$@"
