#!/bin/bash
# Yabomish 三平台 build+test+install 管線（self CI/CD）
# 用法：
#   bash tools/all_platforms.sh test    — 三平台測試
#   bash tools/all_platforms.sh build   — 三平台 build
#   bash tools/all_platforms.sh install — build + 裝置安裝（macOS 本機 / iPhone USB）
#   bash tools/all_platforms.sh all     — 全部

set -e
MACOS=/Users/fl/Python/yabomish
IOS=/Users/fl/Python/yabomish_ios
ANDROID=/Users/fl/Python/yabomish_android
IOS_DEVICE=0E5B33F4-29EA-57FC-A4B7-859A61612F2C
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
SIM="iPhone 17 Pro"

ok()   { printf "\033[32m[OK]\033[0m %s\n" "$1"; }
fail() { printf "\033[31m[FAIL]\033[0m %s\n" "$1"; exit 1; }

macos_test() {
  cd "$MACOS" && bash YabomishIM/Tests/run_tests.sh 2>&1 | tail -1 | grep -q '0 failed' \
    && ok "macOS: 88+ tests passed" || fail "macOS tests"
}
macos_build() {
  cd "$MACOS" && printf '2\n1\n' | bash yabomish.sh 2>&1 | grep -qE '\[OK\] YabomishIM' \
    && ok "macOS: build full" || fail "macOS build"
}
macos_install() {
  rm -rf ~/Library/Input\ Methods/YabomishIM.app
  cp -R "$MACOS/YabomishIM/build/YabomishIM.app" ~/Library/Input\ Methods/
  codesign -s - --force --deep ~/Library/Input\ Methods/YabomishIM.app 2>/dev/null
  killall YabomishIM 2>/dev/null || true
  ok "macOS: installed to ~/Library/Input Methods"
}

ios_test() {
  cd "$IOS" && xcodebuild test -project Yabomish.xcodeproj -scheme YabomishTests \
    -destination "platform=iOS Simulator,name=$SIM" 2>&1 | grep -E 'Executed.*tests,' | tail -1 | grep -q ' 0 failures' \
    && ok "iOS: tests passed" || fail "iOS tests"
}
ios_build() {
  for s in YabomishApp YabomishKeyboard YabomishTests; do
    xcodebuild build -project "$IOS/Yabomish.xcodeproj" -scheme $s \
      -destination "platform=iOS Simulator,name=$SIM" 2>&1 | grep -q 'BUILD SUCCEEDED' \
      && ok "iOS: $s build" || fail "iOS $s build"
  done
}
ios_install() {
  xcodebuild build -project "$IOS/Yabomish.xcodeproj" -scheme YabomishApp \
    -destination "id=$IOS_DEVICE" -allowProvisioningUpdates 2>&1 | grep -q 'BUILD SUCCEEDED' \
    || fail "iOS device build"
  local app
  app=$(find ~/Library/Developer/Xcode/DerivedData -name 'YabomishApp.app' -path '*iphoneos*' | head -1)
  xcrun devicectl device install app --device "$IOS_DEVICE" "$app" 2>&1 | grep -q 'App installed' \
    && ok "iOS: installed to iPhone" || fail "iOS install（裝置有接上嗎？）"
}

android_test() {
  cd "$ANDROID" && export JAVA_HOME
  ./gradlew compileDebugKotlin -q 2>&1 || fail "Android compile"
  ok "Android: compile passed（無 unit test 套件）"
}
android_build() {
  cd "$ANDROID" && export JAVA_HOME
  ./gradlew assembleDebug 2>&1 | grep -q 'BUILD SUCCESSFUL' \
    && ok "Android: APK $(ls -lh app/build/outputs/apk/debug/app-debug.apk 2>/dev/null | awk '{print $5}')" \
    || fail "Android build"
}

case "${1:-all}" in
  test)    macos_test; ios_test; android_test ;;
  build)   macos_build; ios_build; android_build ;;
  install) macos_build; macos_install; ios_build; ios_install; android_build ;;
  all)     macos_test; ios_test; android_test; macos_build; ios_build; android_build; macos_install ;;
  *) echo "用法: $0 {test|build|install|all}"; exit 1 ;;
esac
ok "=== 管線完成 ==="
