# ,, 指令系統演化 — 從輸入法到 Inline Agent

日期：2026-04-22
狀態：設計討論，待實作

## 核心洞見

輸入法是 macOS 上唯一一個永遠活在所有 app 裡的程式。它攔截每一個按鍵、有游標位置、有候選區可顯示資訊、能直接送文字進任何 text field。對重度中文打字者而言，home row 就是 command line。

`,, ` 系統不是取代系統功能，是提供一個手不離 home row 的替代入口。

## 判斷標準

> 這個操作會不會在你打字的時候發生？

會 → 放進 `,,` 系統就有價值。跟結果是文字或非文字無關。

## 兩條軸線

### 軸線一：文字處理（內建，Swift 硬寫）

結果直接進游標，要快、要穩、要零延遲。數量有限、邏輯固定、不常改。

| 指令 | 功能 |
|------|------|
| `,,v` | 清格式貼上（純文字，去除 HTML/RTF 格式） |
| `,,vm` | 貼上並轉 Markdown（HTML → MD） |
| `,,vt` | 貼上並簡→繁 |
| `,,vr` | 貼上並繁→簡 |
| `,,G` | HLS 語義搜尋（已實作） |

`,,v` 是最大眾的痛點：每個人都遇過從網頁複製貼進 Word 格式全亂。Cmd+Shift+Option+V 四個鍵且不是每個 app 都支援。`,,v` 四個鍵，任何 app 都一樣。

### 軸線二：系統腳本（外部，JSON + shell）

走 `commands.json`，Yabomish 只負責讀檔 + Process 執行。加新指令不碰 Swift。

```json
// ~/Library/YabomishIM/commands.json
{
  "sf": { "type": "open", "app": "Safari" },
  "gh": { "type": "open", "app": "Ghostty" },
  "li": { "type": "open", "app": "LINE" },
  "cc": { "type": "shell", "run": "open -a Ghostty && sleep 0.5 && ..." },
  "r":  { "type": "shell", "run": "open -a 'Voice Memos'" },
  "mt": { "type": "shell", "run": "open -a 'Voice Memos' && open 'obsidian://new?vault=Work&name=Meeting-$(date +%Y%m%d-%H%M)'" }
}
```

使用情境：
- `,,sf` 切 Safari — 比 Cmd+Tab 在一排 icon 裡找更直接
- `,,cc` 開 Ghostty + Claude Code — 一個指令串兩步
- `,,li` 切 LINE — 打字打到一半回訊息，手不離鍵盤
- `,,mt` 開會模式 — 錄音 + 開 Obsidian 新筆記

## Dispatch 架構

```
,, + 指令 → 先查內建表 → 沒有 → 再查 commands.json
```

內建優先，外部兜底。文字處理的效能不受影響，系統腳本的彈性不受限。

## MCP 整合（未來）

暴露 `list_yabomish_commands` / `upsert_yabomish_command` 兩個 tool，讓 AI agent 能讀寫 commands.json。用戶對 Claude 說「幫我加一個 ,,mt」，agent 組好 shell script 寫進 JSON，完成。

Yabomish = 執行層，Agent = 編程層，commands.json = 契約。

## 不適合的場景

- 螢幕亮度、音量等連續調整 — 有專用硬體鍵，且需要連續操作
- 複雜互動流程 — 候選區只有一列，沒有二級選單
- 但如果使用者確實在打字中需要這些操作，仍可考慮加入

## 產品策略

- 軸線一（文字處理）先出，`,,v` 是殺手功能，所有人都痛
- 軸線二（系統腳本）自己先用，確認哪些指令真的每天在用
- 不急著發版，先自用沉澱
- `,,v` 系列有自然的 power user 養成路徑：從清格式進來，自己發現轉 MD、轉簡繁
