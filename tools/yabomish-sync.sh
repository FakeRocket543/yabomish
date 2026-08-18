#!/bin/zsh
# yabomish-sync.sh — v2 多後端同步（R2 / GitHub HTTPS / private git SSH/HTTPS）
# 用法：yabomish-sync.sh [push|pull|status]
#
# 後端由 YABOMISH_SYNC_BACKEND 決定：
#   r2        — 經 vos3 daemon 同步到 R2（預設，舊版相容）
#   git       — 經 git 同步到 GitHub / Forgejo / 任何 git repo
#               公開用 https://github.com/user/repo.git
#               私密用 https://github.com/user/repo.git + YABOMISH_SYNC_TOKEN
#               私密也可用 ssh：git@git.lcn.tw:user/repo.git
#
# 環境變數：
#   YABOMISH_SYNC_BACKEND        r2 | git
#   YABOMISH_SYNC_REPO           git repo URL
#   YABOMISH_SYNC_TOKEN          HTTPS personal access token
#   YABOMISH_SYNC_BRANCH         預設 main
#   YABOMISH_SYNC_NAME           git committer name（預設 Yabomish）
#   YABOMISH_SYNC_EMAIL          git committer email（預設 sync@yabomish.local）

set -e

BACKEND="${YABOMISH_SYNC_BACKEND:-r2}"
SHARE_DIR="${YABOMISH_SHARE_DIR:-$HOME/Library/Application Support/Yabomish}"
# 同步檔案清單（v2 新增 user_snippets.json）
FILES=(commands.json char_freq.json user_snippets.json contexts/ch.json contexts/df.json contexts/tc.json contexts/tw.json)

cmd="${1:-push}"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
mtime() { stat -f '%m' "$1" 2>/dev/null || echo 0; }

# ── R2 後端 ─────────────────────────────────────────────────

r2_status() {
  local VOS3_SOCKET="${VOS3_SOCKET:-/Users/fl/Library/Application Support/cc.vos3.daemon/daemon.sock}"
  local REMOTE_ID="${YABOMISH_VOS3_REMOTE:-943fff7c-122a-4549-9557-fcb296cfcd6c}"
  local PREFIX="yabomish-sync"
  local VOS3=(vos3 --socket "$VOS3_SOCKET")
  local TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  local MANIFEST="$PREFIX/manifest.json"
  local RMAN
  vos3_get() { local rp="$1" lp="$2"; touch "$lp" && "${VOS3[@]}" get "$REMOTE_ID" "$rp" "$lp"; }
  if vos3_get "$MANIFEST" "$TMP/manifest.json" >/dev/null 2>&1; then RMAN=$(cat "$TMP/manifest.json"); else RMAN='{}'; fi

  jkey() { echo "$1" | tr '/.' '__'; }
  echo "── backend: r2 ──"
  echo "── local ──"
  for f in "${FILES[@]}"; do
    [ -f "$SHARE_DIR/$f" ] && echo "$(mtime "$SHARE_DIR/$f")  $(sha "$SHARE_DIR/$f" | cut -c1-8)  $f" || echo "-  -  $f (missing)"
  done
  echo "── remote manifest ──"
  if [ "$RMAN" != "{}" ]; then echo "$RMAN" | jq -r '.files // {} | to_entries[] | "\(.value.mtime)  \(.value.sha256[0:8])  \(.key)"' 2>/dev/null; else echo "(no remote manifest — run push first)"; fi
}

r2_pull() {
  local VOS3_SOCKET="${VOS3_SOCKET:-/Users/fl/Library/Application Support/cc.vos3.daemon/daemon.sock}"
  local REMOTE_ID="${YABOMISH_VOS3_REMOTE:-943fff7c-122a-4549-9557-fcb296cfcd6c}"
  local PREFIX="yabomish-sync"
  local VOS3=(vos3 --socket "$VOS3_SOCKET")
  local TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  local MANIFEST="$PREFIX/manifest.json"
  local RMAN
  vos3_get() { local rp="$1" lp="$2"; touch "$lp" && "${VOS3[@]}" get "$REMOTE_ID" "$rp" "$lp"; }
  if vos3_get "$MANIFEST" "$TMP/manifest.json" >/dev/null 2>&1; then RMAN=$(cat "$TMP/manifest.json"); else RMAN='{}'; fi

  jkey() { echo "$1" | tr '/.' '__'; }
  for f in "${FILES[@]}"; do
    local RM=$(echo "$RMAN" | jq -r ".files[\"$(jkey "$f")\"].mtime // 0" 2>/dev/null || echo 0)
    local LOCAL_M=$(mtime "$SHARE_DIR/$f")
    if [ "$LOCAL_M" -eq 0 ] || { [ "$LOCAL_M" -lt "$RM" ] && [ "$RM" != 0 ]; }; then
      mkdir -p "$(dirname "$SHARE_DIR/$f")"
      if vos3_get "$PREFIX/$f" "$SHARE_DIR/$f" >/dev/null 2>&1; then echo "↓ $f"; else echo "✗ $f (download failed)"; fi
    else
      echo "= $f (local newer or equal)"
    fi
  done
}

r2_push() {
  local VOS3_SOCKET="${VOS3_SOCKET:-/Users/fl/Library/Application Support/cc.vos3.daemon/daemon.sock}"
  local REMOTE_ID="${YABOMISH_VOS3_REMOTE:-943fff7c-122a-4549-9557-fcb296cfcd6c}"
  local PREFIX="yabomish-sync"
  local VOS3=(vos3 --socket "$VOS3_SOCKET")
  local TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  local MANIFEST="$PREFIX/manifest.json"
  local NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local RMAN
  vos3_get() { local rp="$1" lp="$2"; touch "$lp" && "${VOS3[@]}" get "$REMOTE_ID" "$rp" "$lp"; }
  vos3_put() { "${VOS3[@]}" put "$1" "$2"; }
  if vos3_get "$MANIFEST" "$TMP/manifest.json" >/dev/null 2>&1; then RMAN=$(cat "$TMP/manifest.json"); else RMAN='{}'; fi

  jkey() { echo "$1" | tr '/.' '__'; }
  local CHANGED=0
  for f in "${FILES[@]}"; do
    [ -f "$SHARE_DIR/$f" ] || continue
    local RM=$(echo "$RMAN" | jq -r ".files[\"$(jkey "$f")\"].sha256 // \"none\"" 2>/dev/null || echo none)
    local LS=$(sha "$SHARE_DIR/$f")
    if [ "$RM" != "$LS" ]; then
      if vos3_put "$SHARE_DIR/$f" "$PREFIX/$f" >/dev/null 2>&1; then
        echo "↑ $f"
        RMAN=$(echo "$RMAN" | jq --arg k "$(jkey "$f")" --arg s "$LS" --argjson m "$(mtime "$SHARE_DIR/$f")" '.files[$k] = {sha256: $s, mtime: $m}')
        CHANGED=1
      else
        echo "✗ $f (upload failed)"
      fi
    else
      echo "= $f (unchanged)"
    fi
  done
  if [ "$CHANGED" = 1 ]; then
    RMAN=$(echo "$RMAN" | jq --arg u "$NOW" '.updated_at = $u | .schema = 1')
    echo "$RMAN" > "$TMP/manifest-out.json"
    if vos3_put "$TMP/manifest-out.json" "$MANIFEST" >/dev/null 2>&1; then echo "↑ manifest.json"; fi
  fi
}

# ── Git 後端 ─────────────────────────────────────────────────

git_status() {
  echo "── backend: git ──"
  echo "repo: $YABOMISH_SYNC_REPO"
  echo "── local ──"
  for f in "${FILES[@]}"; do
    [ -f "$SHARE_DIR/$f" ] && echo "$(mtime "$SHARE_DIR/$f")  $(sha "$SHARE_DIR/$f" | cut -c1-8)  $f" || echo "-  -  $f (missing)"
  done
}

git_url() {
  local url="$YABOMISH_SYNC_REPO"
  if [ -n "${YABOMISH_SYNC_TOKEN:-}" ] && [[ "$url" == https://* ]]; then
    # https://github.com/user/repo.git → https://x-access-token:TOKEN@github.com/...
    url="${url/https:\/\//https:\/\/x-access-token:$YABOMISH_SYNC_TOKEN@}"
  fi
  echo "$url"
}

git_sync_dir() {
  local TMP=$(mktemp -d)
  local url=$(git_url)
  local branch="${YABOMISH_SYNC_BRANCH:-main}"
  # 淺 clone；失敗時初始化空 repo
  if ! git clone --depth=1 --branch="$branch" "$url" "$TMP/repo" >/dev/null 2>&1; then
    mkdir -p "$TMP/repo"
    git init "$TMP/repo" >/dev/null
    git -C "$TMP/repo" remote add origin "$url" >/dev/null 2>&1 || true
  fi
  echo "$TMP"
}

git_pull() {
  [ -n "$YABOMISH_SYNC_REPO" ] || { echo "錯誤：YABOMISH_SYNC_REPO 未設定"; exit 1; }
  local TMP=$(git_sync_dir)
  trap 'rm -rf "$TMP"' EXIT
  local repo="$TMP/repo"
  for f in "${FILES[@]}"; do
    if [ -f "$repo/$f" ]; then
      mkdir -p "$(dirname "$SHARE_DIR/$f")"
      cp "$repo/$f" "$SHARE_DIR/$f"
      echo "↓ $f"
    else
      echo "- $f (remote missing)"
    fi
  done
}

git_push() {
  [ -n "$YABOMISH_SYNC_REPO" ] || { echo "錯誤：YABOMISH_SYNC_REPO 未設定"; exit 1; }
  local name="${YABOMISH_SYNC_NAME:-Yabomish}"
  local email="${YABOMISH_SYNC_EMAIL:-sync@yabomish.local}"
  export GIT_AUTHOR_NAME="$name"
  export GIT_AUTHOR_EMAIL="$email"
  export GIT_COMMITTER_NAME="$name"
  export GIT_COMMITTER_EMAIL="$email"

  local TMP=$(git_sync_dir)
  trap 'rm -rf "$TMP"' EXIT
  local repo="$TMP/repo"
  local branch="${YABOMISH_SYNC_BRANCH:-main}"
  local url=$(git_url)

  # 確保本地分支名稱正確
  git -C "$repo" checkout -b "$branch" 2>/dev/null || true

  # 複製本地檔案到 repo
  local CHANGED=0
  for f in "${FILES[@]}"; do
    [ -f "$SHARE_DIR/$f" ] || continue
    mkdir -p "$(dirname "$repo/$f")"
    if [ -f "$repo/$f" ] && diff -q "$SHARE_DIR/$f" "$repo/$f" >/dev/null 2>&1; then
      echo "= $f (unchanged)"
    else
      cp "$SHARE_DIR/$f" "$repo/$f"
      echo "↑ $f"
      CHANGED=1
    fi
  done

  if [ "$CHANGED" = 0 ]; then
    echo "(no changes to push)"
    return
  fi

  git -C "$repo" add -- "${FILES[@]}"
  if ! git -C "$repo" commit -m "Yabomish sync: $NOW" >/dev/null 2>&1; then
    echo "(nothing changed)"
    return
  fi

  if git -C "$repo" push "$url" "HEAD:$branch" >/dev/null 2>&1; then
    echo "↑ synced to $YABOMISH_SYNC_REPO"
    return
  fi

  echo "✗ push failed; trying pull + rebase..."
  if git -C "$repo" pull --rebase "$url" "$branch" >/dev/null 2>&1; then
    if git -C "$repo" push "$url" "HEAD:$branch" >/dev/null 2>&1; then
      echo "↑ synced to $YABOMISH_SYNC_REPO"
    else
      echo "✗ push failed after rebase"
      exit 1
    fi
  else
    echo "✗ merge conflict; please resolve manually"
    exit 1
  fi
}

# ── 主程式 ───────────────────────────────────────────────────

case "$BACKEND" in
  r2)
    case "$cmd" in status) r2_status;; pull) r2_pull;; push) r2_push;; *) echo "usage: $0 [push|pull|status]"; exit 1;; esac
    ;;
  git)
    case "$cmd" in status) git_status;; pull) git_pull;; push) git_push;; *) echo "usage: $0 [push|pull|status]"; exit 1;; esac
    ;;
  *)
    echo "未知後端：$BACKEND"; echo "請設定 YABOMISH_SYNC_BACKEND=r2 或 git"; exit 1
    ;;
esac
