# ,,g → Hermes：輸入法作為 agent 擷取面（capture surface）

日期：2026-08-18
狀態：構想定案，未實作

## 核心想法

Yabomish 不接 LLM、不碰網路邏輯，只當 **fire-and-forget 擷取入口**：
任何 app 裡打 `,,g <任務>` → POST 一次 → toast「已送出」→ 繼續原工作。
執行、查庫、排程全部在 Hermes 端；結果 deliver 回 Telegram，
使用者 在 TG 回覆即可繼續指揮（attach_to_session / cron）。

這是 GTD ubiquitous capture，捕捉對象從「筆記軟體」換成「agent」。

## 架構

```
Yabomish ,,<cmd> [args]
  → ~/Library/Application Support/Yabomish/yabomish_send.sh
  → curl -m 5 POST http://127.0.0.1:8644/webhooks/yabomish   (HMAC 簽名)
  → Hermes agent run（全套工具：terminal、file、gbrain MCP、cron）
  → 結果 deliver → Telegram
```

角色分工：
- **IME**：擷取面。零等待、零輪詢、零網路代碼（僅 curl 一行）。
  進程掛掉重啟不影響已送出任務。
- **Hermes**：執行面。webhook 是內建事件入口（gateway 127.0.0.1:8644），
  負責 agent run、重試、排程（agent 自己建 cron job）。
- **TG**：結果面。已在用的通道，回覆即續談。

## 為什麼不讓 IME 直接接 LLM/gbrain

1. 延遲預算：打字熱路徑（組字→候選→上屏）<50ms，本機 .bin 才做得到。
   LLM 500ms–數秒，塞進候選排序 = 打字卡頓。
2. 隱私：IME 看得到所有 app 的輸入，ambient LLM 呼叫 = 擊鍵流送遠端。
3. 穩定性：IMK process 掛 = 全系統打字死掉。網路代碼不進 IME 進程。

LLM 適合的位置是離線批次：FreqTracker 語料 → 定期生成 UserPhrases 候選。

## IME insertText 作為「LLM 輸出萬用橋接」的定位

macOS 上唯一的零額外權限萬用輸出路徑：

| 機制 | 萬用性 | 權限 | 副作用 |
|---|---|---|---|
| IME insertText | ★★★ | 無 | 無 |
| 剪貼簿+Cmd+V（,,v 現有） | ★★★ | TCC Accessibility | 蓋剪貼簿 |
| CGEvent 逐鍵 | ★★ | TCC | 慢、可側錄 |
| AXUIElement setValue | ★ | TCC | Electron/終端常失效 |

前例：fcitx5-vinput（386★，語音→LLM 改寫→commit）、
madeye/ds-input（52★，拼音→LLM 整句）、
librime-llmresponse-display（檔案佇列模式，IME 零 LLM 代碼）。
「IME × Hermes × 私料庫」組合目前無公開前例。

## 與「結果回到游標」的取捨

本設計放棄結果即時回游標（候選面板顯示），換：
- IME 進程零網路、零狀態
- 結果非同步回 TG，消化時機自選
- 長任務（研究、下載、build）不需開視窗顧

## 現有程式碼基礎（0.3.60）

- `CommaCommandRunner`：text/open/shell 三型，shell 走
  `_runShellAsync`（DispatchQueue.global + 5s 逾時）— fire-and-forget 天然合適
- 前綴帶參數前例：`unpina` → `cmd.hasPrefix("unpin") + dropFirst(5)`
  （InputEngine.swift L600）
- `ClipboardProcessor`：剪貼簿 fallback 可零改動取得中文內容

## 已知缺口

1. `_commaCommandBuffer` 只收 ASCII 擊鍵，中文進不去（會先走組字）。
   - 方案 A（零改動）：`,,g` 無參數 → 送剪貼簿內容
   - 方案 B（~40 行 engine 改動）：capture 模式，commit 的字 append 進
     buffer 而非送出 app，Enter 才整串送走
2. commands.json 的 shell 型目前不帶 buffer 參數給腳本 — 需加
   「指令後剩餘字串作 argv」
3. Hermes 端還沒 subscribe（目前 0 個 subscription）

## 實作順序

1. Hermes 端：`hermes webhook subscribe yabomish`
   （prompt 模板帶 `{text}`，deliver telegram）— 10 分鐘
2. `yabomish_send.sh`：curl + HMAC 簽名、5s 逾時、fire-and-forget
3. commands.json 加 `,,g`（shell 型）
4. 測試 POST → TG 收到 → 鏈路驗證
5. 之後：Swift 方案 B（中文 capture 模式）
6. 可選：cloudflared tunnel（手機/m6 也能 POST 進來）

## 延伸：三層延遲架構（之後可做）

- Tier 1（<50ms 熱路徑）：現狀，本機 .bin + freq.db
- Tier 2（~100ms 非同步 prefetch）：gbrain Postgres FTS 直查（read-only），
  私料候選列在次要面板，主動選才插入
- Tier 3（秒級，明確觸發）：本篇的 `,,g` → Hermes

contexts/（ch/df/tc/tw.json）是現成 per-app 路由鉤子：
不同 app 查不同私料子集。
