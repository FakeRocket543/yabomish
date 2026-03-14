#!/bin/bash
# 打包 Yabomish DMG
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="YabomishIM"
VERSION=$(defaults read "$SCRIPT_DIR/YabomishIM/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "0.0.0")
DMG_NAME="Yabomish-${VERSION}"
STAGING="$SCRIPT_DIR/dmg_staging"

echo "=== 打包 Yabomish v${VERSION} DMG ==="

# 1. 編譯
echo "→ 編譯..."
cd "$SCRIPT_DIR/YabomishIM" && bash build.sh

# 2. 準備 staging 目錄
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$SCRIPT_DIR/YabomishIM/build/$APP_NAME.app" "$STAGING/"
cp "$SCRIPT_DIR/Install.command" "$STAGING/"
chmod +x "$STAGING/Install.command"

# 3. 簽名（如有 Developer ID）
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
if [ -n "$IDENTITY" ]; then
    echo "→ 簽名: $IDENTITY"
    codesign --deep --force --options runtime --sign "$IDENTITY" "$STAGING/$APP_NAME.app"
else
    echo "⚠️  未找到 Developer ID，跳過簽名"
fi

# 4. 建立 DMG
echo "→ 建立 DMG..."
rm -f "$SCRIPT_DIR/$DMG_NAME.dmg"
hdiutil create -volname "$DMG_NAME" -srcfolder "$STAGING" \
    -ov -format UDZO "$SCRIPT_DIR/$DMG_NAME.dmg"

# 5. 簽名 DMG
if [ -n "$IDENTITY" ]; then
    codesign --sign "$IDENTITY" "$SCRIPT_DIR/$DMG_NAME.dmg"
fi

# 6. Notarize（如有 keychain profile）
if xcrun notarytool history --keychain-profile "notary" >/dev/null 2>&1; then
    echo "→ Notarize..."
    xcrun notarytool submit "$SCRIPT_DIR/$DMG_NAME.dmg" \
        --keychain-profile "notary" --wait
    xcrun stapler staple "$SCRIPT_DIR/$DMG_NAME.dmg"
    echo "✅ Notarize 完成"
else
    echo "⚠️  未設定 notary keychain profile，跳過 notarize"
    echo "   設定方式: xcrun notarytool store-credentials notary --apple-id <email> --team-id <team>"
fi

# 清理
rm -rf "$STAGING"

echo ""
echo "✅ DMG 已建立: $SCRIPT_DIR/$DMG_NAME.dmg"
ls -lh "$SCRIPT_DIR/$DMG_NAME.dmg"
