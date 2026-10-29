# Prompt Mode 實作計畫

日期：2026-10-29  
狀態：計畫，未實作  
依據：`docs/design/20261029-prompt-mode-feasibility.md`

## 目標

加入一個明確觸發的 `,,` prompt mode，使用 macOS 27 內建 `/usr/bin/fm`，
將 LLM 輸出 commit 到游標。定位為 Tier 3 生成器，不做 agent/web-search，
不做系統權限查詢。

## 命令設計

- 首選命令：`,,LLM`（避免 `,,P` 設定程式、`,,g` Hermes capture 衝突）
- 備選：`,,AI`（若不與使用者 commands.json 的 `ai` 衝突）
- MVP 先支援無空白 prompt：`,,LLM <prompt>`，空格觸發
- 後續再做互動式 prompt mode（支援空白、Enter 提交、Esc 取消）

## 架構

1. `InputEngine._dispatchCommaCommand` 新增 `llm` 分支
2. 非同步呼叫：
   - executable: `/usr/bin/fm`
   - args: `["respond", prompt]`
   - stdout pipe 讀取完整輸出
   - timeout: 30 秒（不要沿用 5 秒）
3. 回呼：
   - 若原 client 仍有效且焦點未切換 → `engineDidCommit(output)`
   - 否則 → 寫入 pasteboard + toast「結果已放入剪貼簿」
4. 提交前 toast：「LLM 生成中…」
5. 失敗（fm 不存在、license 未同意、模型不可用、逾時）→ toast 錯誤

## Enter 處理

- `InputEngine.handleEnter` 目前會 dispatch comma command
- prompt mode 必須在 Enter 前攔截，提交 buffer，不能落入一般 dispatch

## 逾時與取消

- Process watchdog 30 秒
- 使用者切換 app / 開始新輸入時，丟棄舊結果

## 測試計畫

1. 單元測試：command decode、dispatch、timeout fallback（可 mock Process）
2. 手動測試：
   - `, ,LLM 寫一句過年祝賀`
   - 多行輸出 commit
   - fm license 未同意時的錯誤 toast
   - 焦點切換時 fallback pasteboard
3. 編譯矩陣：IM full / IM MINIMAL / Prefs

## 文件更新

- `docs/usage.md` 補上 `,,LLM`
- `CommaCommandHelp` 補說明
- README 快速參考可選補充

## 非目標

- 不做 web search / agent orchestration
- 不做系統權限查詢
- 不做候選字/聯想引擎整合
- 不儲存 provider credential