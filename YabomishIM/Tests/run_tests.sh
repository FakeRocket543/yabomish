#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Standalone test compilation — no app source dependencies.
# InputEngine has deep Cocoa transitive deps (YabomishPrefs, DomainOrderManager, etc.)
# so we test the delegate protocol + mock in isolation for now.
TEST_SOURCES=$(find Tests -name '*.swift')

echo "Compiling test runner..."
swiftc \
    -module-name YabomishTests \
    -target arm64-apple-macos14.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework Foundation \
    -o /tmp/yabomish_tests \
    $TEST_SOURCES 2>&1

echo "Running tests..."
/tmp/yabomish_tests
