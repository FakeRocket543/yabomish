#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="YabomishPrefs.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

swiftc \
    -module-name YabomishPrefs \
    -target arm64-apple-macos14.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework SwiftUI \
    -framework AppKit \
    -framework UniformTypeIdentifiers \
    -O \
    -o "$APP/Contents/MacOS/YabomishPrefs" \
    Sources/*.swift

chmod +x "$APP/Contents/MacOS/YabomishPrefs"
echo "Built $APP"
