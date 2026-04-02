#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/Sources"
RES_DIR="$SCRIPT_DIR/Resources"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="YabomishIM"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
MODULE_NAME="YabomishIM"

echo "=== 編譯 Yabomish ==="

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy Info.plist
cp "$RES_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy icons
if [ -f "$RES_DIR/icon.tiff" ]; then
    cp "$RES_DIR/icon.tiff" "$APP_BUNDLE/Contents/Resources/"
fi
if [ -f "$RES_DIR/icon.icns" ]; then
    cp "$RES_DIR/icon.icns" "$APP_BUNDLE/Contents/Resources/"
fi
if [ -f "$RES_DIR/icon_right.tiff" ]; then
    cp "$RES_DIR/icon_right.tiff" "$APP_BUNDLE/Contents/Resources/"
fi
if [ -f "$RES_DIR/icon_left.tiff" ]; then
    cp "$RES_DIR/icon_left.tiff" "$APP_BUNDLE/Contents/Resources/"
fi
# Copy zhuyin data
if [ -f "$RES_DIR/zhuyin_data.json" ]; then
    cp "$RES_DIR/zhuyin_data.json" "$APP_BUNDLE/Contents/Resources/"
fi
# Copy pinyin data
if [ -f "$RES_DIR/pinyin_data.json" ]; then
    cp "$RES_DIR/pinyin_data.json" "$APP_BUNDLE/Contents/Resources/"
fi
# Copy character maps
for f in t2s.json s2t.json char_freq.json bigram_boost.json; do
    if [ -f "$RES_DIR/$f" ]; then
        cp "$RES_DIR/$f" "$APP_BUNDLE/Contents/Resources/"
    fi
done

# Write PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Compile
SWIFT_FILES=$(find "$SRC_DIR" -name "*.swift" | sort)
echo "Compiling: $SWIFT_FILES"

swiftc \
    -module-name "$MODULE_NAME" \
    -target arm64-apple-macos14.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    -O \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    $SWIFT_FILES

echo "=== 編譯完成: $APP_BUNDLE ==="
echo ""
echo "下一步: ./install.sh"
