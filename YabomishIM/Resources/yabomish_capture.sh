#!/bin/zsh
# yabomish_capture.sh — screenshot helper for ,, commands
# Usage: yabomish_capture.sh [screen|window|select]
# Always saves to Desktop AND copies to clipboard.
set -euo pipefail

MODE="${1:-screen}"
SHOT_DIR="$HOME/Desktop"
FILE="$SHOT_DIR/shot-$(date +%Y%m%d-%H%M%S).png"

notify() {
    osascript -e "display notification \"$1\" with title \"Yabomish\"" 2>/dev/null
}

case "$MODE" in
    screen)
        screencapture -x "$FILE"
        ;;
    window)
        WID=$(python3 -c "
import Quartz, subprocess
r = subprocess.run(['osascript','-e','tell application \"System Events\" to unix id of first process whose frontmost is true'], capture_output=True, text=True)
pid = int(r.stdout.strip())
wl = Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements, Quartz.kCGNullWindowID)
for w in wl:
    if w.get('kCGWindowOwnerPID') == pid and w.get('kCGWindowLayer', 999) == 0:
        print(w['kCGWindowNumber']); break
" 2>/dev/null)
        if [[ -z "$WID" ]]; then notify "找不到當前視窗"; exit 1; fi
        screencapture -x -l"$WID" "$FILE"
        ;;
    select)
        screencapture -i "$FILE"
        [[ -f "$FILE" ]] || exit 0  # user cancelled with Esc
        ;;
esac

if [[ -f "$FILE" ]]; then
    osascript -e "set the clipboard to (read POSIX file \"$FILE\" as «class PNGf»)"
    notify "截圖已存到桌面"
else
    # screencapture failed silently — likely no screen recording permission
    notify "截圖失敗 — 請到 系統設定 → 隱私權 → 螢幕錄製 開啟權限"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
fi
