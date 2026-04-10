#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# UI-only files to exclude
EXCLUDE="PrefsWindow|CandidatePanel|DomainCardView|DomainCollectionController|ModeToast|AppDelegate|DataDownloader|YabomishInputController|PhraseLookup|DebugLog"

SOURCES=$(find Sources Sources/Shared -maxdepth 1 -name '*.swift' | grep -Ev "$EXCLUDE" | sort -u)
TEST_SOURCES=$(find Tests -name '*.swift' | sort)

echo "Compiling test runner..."
swiftc \
    -module-name YabomishTests \
    -target arm64-apple-macos14.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework Foundation \
    -framework AppKit \
    -framework Cocoa \
    -lsqlite3 \
    -O \
    -o /tmp/yabomish_tests \
    $SOURCES $TEST_SOURCES 2>&1

echo "Running tests..."
/tmp/yabomish_tests
