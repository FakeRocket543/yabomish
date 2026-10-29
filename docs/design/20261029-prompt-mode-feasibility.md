# Prompt Mode（`,,AI` / `,,p`）與 macOS Apple Foundation Models (`fm`) 可行性研究

日期：2026-10-29  
狀態：研究結論，未實作

## 使用者想法

在 Yabomish 中加入獨特的 `,,` prompt 模式，連接 macOS 版 Apple Foundation Models LLM，
讓 LLM 輸出的文字直接透過輸入法上屏（commit to cursor）。

## 關鍵發現

1. **macOS 27 內建 CLI 是 `/usr/bin/fm`，不是 `afm`**
   - 本機 `which afm` 失敗；`which fm` = `/usr/bin/fm`。
   - `fm available` 回 `System model available`。
   - `fm respond --stream '...'` 可用，短 prompt 約 1 秒。
   - 需先 `sudo fm license` 全機同意條款，否則 IME 內呼叫會失敗。

2. **現有架構已有可複用的非同步派送基礎**
   - `CommaCommandRunner.tryExecute` 支援 `shell` / `open` / `hermes`。
   - `_runProcessAsync` 使用 `Process` + pipe + 5 秒 watchdog + SIGKILL 升級，不卡主執行緒。
   - `engineDidCommit` / `engineDidPasteText` 已能送出多行文字。
   - `InputEngine._commaCommandBuffer` 只收 ASCII 擊鍵且空格觸發 dispatch，不適合直接承載含空白 prompt。

3. **權限與執行環境**
   - `Info.plist` 未見 App Sandbox；Process 呼叫 `/usr/bin/fm` 可行。
   - IMK process 長駐；非同步回呼時焦點可能已切換，必須 guard `engineClient` / `isDeactivating`。

## 內建 `,,` 命令占用現況

已占用單字母 / 前綴：

- 模式：`t` `s` `sp` `sl` `ts` `st` `j`
- 查碼：`zh` `to` `pys` `pyt`
- 系統：`rs` `rl` `lh` `rh` `pin` `unpinx` `sg` `c` `h` `p`
- 剪貼簿：`v` `vt` `vs`
- App 導航：`b` `f`
- 語境：`x` 前綴（`xs` `xi` `xrs` 等）
- 自訂：`commands.json`（`text` / `shell` / `open` / `hermes`）

可選新命令碼（未占用）：`a` `ai` `q` `llm` `pr` 等。  
注意：`g` 已被 `docs/design/20260818-ime-agent-capture.md` 保留為 `,,g` Hermes capture，避免衝突。  
注意：內建命令優先於 `commands.json`，若使用者已有 `ai` 自訂命令，新增 `,,AI` 會 shadow；較安全的 built-in 名稱為 `,,LLM` / `,,PM` / `,,PP`（仍需檢查 commands.json）。
建議用 **`,,AI`**（語意清楚、未占用、不與 `,,P` 設定程式衝突）。

## 可行性結論

**可行，但定位為 Tier 3 明確觸發功能，不可進打字熱路徑。**

- 可用 `/usr/bin/fm respond` 非同步執行，結果透過 `engineDidCommit` 上屏。
- 不應把 LLM 輸出塞進 CIN 候選 / 聯想引擎；延遲與狀態管理成本過高。
- 必須避免 shell 字串拼接 prompt；使用 `Process` arguments 或 stdin。

## 與既有設計的關係

`docs/design/20260818-ime-agent-capture.md` 明確主張 IME 不應直接接 LLM：
延遲預算、隱私、IMK process 穩定性。本研究不推翻該原則，而是把 prompt mode
定位為 **使用者明確觸發、本機 on-device、非同步 commit** 的 Tier 3 功能，
與 `,,g` fire-and-forget capture 互補，而非 ambient LLM。

## 風險 / 限制

1. Apple 條款：fm license Legal Notice 說明不得以程式化方式存取 Apple models，
   除非 expressly permitted；fm CLI 本身就是 scripting 介面，但 IME 呼叫仍需自行評估。
2. Token 上限：system model 4096 tokens，長 prompt / 長輸出會截斷。
3. 回呼時機：非同步完成時可能已離開原 app / 原 client，需防呆。
4. 延遲：每次 prompt 約 1 秒以上，不適合打字熱路徑。
5. 模型可用性：未同意 license 或模型不可用時需 toast 失敗，不可靜默。
6. 終端機授權：`sudo fm license` 為全機設定，安裝流程需考慮。
7. Enter 也會 dispatch comma command（`InputEngine.handleEnter`）；prompt mode 需在 Enter 前攔截並提交 buffer，不能落入一般 dispatch。

## MVP 設計建議

### 方案 A：無空白 prompt（最小改動）

- 命令：`,,AI <prompt>`，prompt 不含空白（或以 `_` 代替空白）。
- 沿用 `_commaCommandBuffer`，Space 觸發後呼叫 `/usr/bin/fm respond`。
- 完成後 `engineDidCommit(output)`。

### 方案 B：互動式 prompt mode（支援空白）

新增 `_isPromptMode` + `_promptBuffer`：

- Enter prompt mode：`,,AI` 後不立即 dispatch。
- 所有字元（含空格）append 到 buffer，marked text 顯示 `AI: <prompt>`。
- Enter 提交、Esc 取消、Backspace 編輯。
- 提交後非同步呼叫 fm，toast「AI 生成中…」，完成後 clear composing 再 commit。

建議先做 A，驗證 Process + pipe + commit 鏈路；再做 B。

## 實作順序

1. 在 `InputEngine._dispatchCommaCommand` 加 `ai` 分支，非同步呼叫 `/usr/bin/fm respond`。
2. toast / marked text / commit 鏈路驗證。
3. 加入逾時（建議 15–30 秒，不要沿用 5 秒）。
4. 更新 `CommaCommandHelp` 說明。
5. 更新 `docs/usage.md`。
6. 若需要， prefs/help 補充。

## 本機驗證記錄

- OS：macOS 27.0.1（Build 26A434）
- `which afm`：not found
- `which fm`：`/usr/bin/fm`
- `fm available`：`System model available`
- `fm respond --stream '用繁體中文回答：蝦子是什麼？一句話'`：約 1.0 秒，輸出「蝦子是一種水生甲殼類動物。」