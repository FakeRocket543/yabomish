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

get_frontmost_wid() {
    swift -e '
import Cocoa
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]],
      let app = NSWorkspace.shared.frontmostApplication else { exit(1) }
let pid = Int(app.processIdentifier)
for w in list {
    if let wp = w["kCGWindowOwnerPID"] as? Int, wp == pid,
       let layer = w["kCGWindowLayer"] as? Int, layer == 0,
       let wid = w["kCGWindowNumber"] as? Int {
        print(wid); exit(0)
    }
}
exit(1)
' 2>/dev/null
}

case "$MODE" in
    screen)
        screencapture -x "$FILE"
        ;;
    window)
        WID=$(get_frontmost_wid)
        if [[ -z "$WID" ]]; then notify "找不到當前視窗"; exit 1; fi
        screencapture -x -l"$WID" "$FILE"
        ;;
    select)
        screencapture -i "$FILE"
        [[ -f "$FILE" ]] || exit 0
        ;;
esac

if [[ -f "$FILE" ]]; then
    osascript -e "set the clipboard to (read POSIX file \"$FILE\" as «class PNGf»)"
    notify "截圖已存到桌面"
else
    notify "截圖失敗 — 請到 系統設定 → 隱私權 → 螢幕錄製 開啟權限"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
fi
