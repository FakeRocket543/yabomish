#!/bin/zsh
# yabomish-sync.sh — v1 檔案同步（macOS 端，經 vos3 daemon）
# 用法：yabomish-sync.sh [push|pull|status]
#   push  — 本地較新 → 上傳 R2（預設）
#   pull  — R2 較新 → 下載覆蓋本地
#   status — 顯示兩側 mtime/hash 差異
VOS3_SOCKET="${VOS3_SOCKET:-/Users/fl/Library/Application Support/cc.vos3.daemon/daemon.sock}"
REMOTE_ID="${YABOMISH_VOS3_REMOTE:-943fff7c-122a-4549-9557-fcb296cfcd6c}"
SHARE_DIR="${YABOMISH_SHARE_DIR:-$HOME/Library/Application Support/Yabomish}"
PREFIX="yabomish-sync"
VOS3=(vos3 --socket "$VOS3_SOCKET")
vos3_get() { local rp="$1" lp="$2"; touch "$lp" && "${VOS3[@]}" get "$REMOTE_ID" "$rp" "$lp"; }
vos3_put() { "${VOS3[@]}" put "$REMOTE_ID" "$1" "$2"; }
MANIFEST="$PREFIX/manifest.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FILES=(commands.json char_freq.json contexts/ch.json contexts/df.json contexts/tc.json contexts/tw.json)

sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
mtime() { stat -f '%m' "$1" 2>/dev/null || echo 0; }

remote_manifest() {
  vos3_get "$MANIFEST" "$TMP/manifest.json" >/dev/null 2>&1 && cat "$TMP/manifest.json" || echo '{}'
}

# jq 欄位路徑：contexts/ch.json → "contexts__ch__json"
jkey() { echo "$1" | tr '/.' '__'; }

cmd="${1:-push}"

case "$cmd" in
status)
  echo "── local ──"
  for f in "${FILES[@]}"; do
    [ -f "$SHARE_DIR/$f" ] && echo "$(mtime "$SHARE_DIR/$f")  $(sha "$SHARE_DIR/$f" | cut -c1-8)  $f" || echo "-  -  $f (missing)"
  done
  echo "── remote manifest ──"
  RMAN="$(remote_manifest)"
  if [ "$RMAN" != "{}" ]; then echo "$RMAN" | jq -r '.files // {} | to_entries[] | "\(.value.mtime)  \(.value.sha256[0:8])  \(.key)"' 2>/dev/null; else echo "(no remote manifest — run push first)"; fi
  ;;
pull)
  MAN="$(remote_manifest)"
  for f in "${FILES[@]}"; do
    RM=$(echo "$MAN" | jq -r ".files[\"$(jkey "$f")\"].mtime // 0" 2>/dev/null || echo 0)
    LOCAL_M=$(mtime "$SHARE_DIR/$f")
    # mtime 0 = 檔案不存在 → 必抓
    if [ "$LOCAL_M" -eq 0 ] || [ "$LOCAL_M" -lt "$RM" ] && [ "$RM" != 0 ]; then
      mkdir -p "$(dirname "$SHARE_DIR/$f")"
      vos3_get "$PREFIX/$f" "$SHARE_DIR/$f" && echo "↓ $f"
    else
      echo "= $f (local newer or equal)"
    fi
  done
  ;;
push)
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  MAN="$(remote_manifest)"
  CHANGED=0
  for f in "${FILES[@]}"; do
    [ -f "$SHARE_DIR/$f" ] || continue
    RM=$(echo "$MAN" | jq -r ".files[\"$(jkey "$f")\"].sha256 // \"none\"" 2>/dev/null || echo none)
    LS=$(sha "$SHARE_DIR/$f")
    if [ "$RM" != "$LS" ]; then
      vos3_put "$SHARE_DIR/$f" "$PREFIX/$f" >/dev/null && echo "↑ $f"
      MAN=$(echo "$MAN" | jq --arg k "$(jkey "$f")" --arg s "$LS" --argjson m "$(mtime "$SHARE_DIR/$f")" \
        '.files[$k] = {sha256: $s, mtime: $m}')
      CHANGED=1
    else
      echo "= $f (unchanged)"
    fi
  done
  if [ "$CHANGED" = 1 ]; then
    MAN=$(echo "$MAN" | jq --arg u "$NOW" '.updated_at = $u | .schema = 1')
    echo "$MAN" > "$TMP/manifest-out.json"
    vos3_put "$TMP/manifest-out.json" "$MANIFEST" >/dev/null && echo "↑ manifest.json"
  fi
  ;;
*) echo "usage: $0 [push|pull|status]"; exit 1;;
esac
