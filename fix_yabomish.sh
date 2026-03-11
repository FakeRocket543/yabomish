#!/bin/bash
# 修復 Yabomish 輸出波斯語的問題
defaults write com.yabomish.plist keyboardLayout "com.apple.keylayout.ABC"
killall YabomishIM 2>/dev/null
echo "Yabomish 已修復，請重新切換輸入法。"
