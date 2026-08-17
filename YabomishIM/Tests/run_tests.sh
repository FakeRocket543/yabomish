#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# UI-only files to exclude
EXCLUDE="CINImportCoordinator|PrefsWindow|CandidatePanel|DomainCardView|DomainCollectionController|DomainOrderManager|ModeToast|AppDelegate|DataDownloader|YabomishInputController|PhraseLookup|DebugLog"

SOURCES=$(find Sources Sources/Shared -maxdepth 1 -name '*.swift' | grep -Ev "$EXCLUDE" | sort -u)
# test_horizontal_panel.swift is a standalone GUI E2E with its own harness — compiled separately
TEST_SOURCES=$(find Tests -name '*.swift' ! -name 'test_horizontal_panel.swift' | sort)

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
