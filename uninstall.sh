#!/bin/bash
# Yabomish 移除腳本
set -e

echo "🦐 Yabomish 移除程式"
echo ""
printf "確定要移除 Yabomish 輸入法？[y/N] "
read -r confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "已取消。"; exit 0; }

killall YabomishIM 2>/dev/null || true
sleep 0.5

echo "移除 /Library/Input Methods/YabomishIM.app ..."
sudo rm -rf "/Library/Input Methods/YabomishIM.app"

echo "清除偏好設定..."
defaults delete com.yabomishim.inputmethod.YabomishIM 2>/dev/null || true

printf "是否一併刪除使用者資料（字表、字頻、擴充表）？[y/N] "
read -r del_data
if [[ "$del_data" =~ ^[Yy]$ ]]; then
    rm -rf ~/Library/YabomishIM
    echo "已刪除 ~/Library/YabomishIM"
fi

echo ""
echo "✅ 移除完成！請登出再登入（或重新開機）。"
