# Shift＋數字鍵輸出選項（macOS 側）— 2026-09-08

> 跨平台功能：macOS（本 repo）＋iOS（yabomish_ios，完整報告見該 repo `doc/20260908-shift-digit.md`）。

## 判定

「聯想顯示時 Shift+數字該輸出符號或數字」存在兩派真實使用者（符號＝全系統肌肉記憶；
數字＝聯想占住裸數字鍵後的插數字出口——舊行為 `// Shift+digit: output digit` 正是為此設計）。
**做成選項，預設符號**；同時修復兩個既有問題。

## 變更

1. **`Prefs.swift`**：新偏好 `shiftDigitOutput`（"symbol" 預設／"digit"；Snapshot＋遷移清單同步）。
2. **`YabomishInputController.swift` shift 區塊**：
   - **修復萬用碼攔截**：原「數字分支在 wildcard 分支之前」，組字中候選非空時 Shift+8 被攔成
     「送出第一候選＋插入字面 8」，README 宣稱的萬用碼在打字途中幾乎不可達（僅零候選字碼漏得過去）。
     現萬用碼分支移至最前，一律生效。
   - 數字分支依偏好輸出 `keyCodeToShifted`（符號，預設）或數字；收候選邏輯不變
     （組字中送第一候選、純聯想收提示）。
   - 行為對齊後消除自相矛盾：原「有候選→數字、idle→符號」改為「有候選→依偏好、idle→恆符號」。
3. **`YabomishPrefs`**：PrefsStore＋InputTab「輸入功能」頁新增兩卡單選（符號／數字，含說明文字）。

## 驗證

- 三目標編譯通過（IM full／MINIMAL／Prefs）。
- 行為矩陣（見 iOS 報告 §2）由分支結構審查＋獨立審查代理覆核（結論：無 P0/P1，主線正確；
  P2 建議中的文案 nit 已修）；IMK 事件路徑無自動化 harness。
- 舊使用者影響：習慣「Shift+數字=數字」者需至輸入頁開啟「數字」卡；CHANGELOG 已記錄行為變更。

## iOS 對應（摘要）

iOS 硬體路徑（iPad 鍵盤）原把 Shift+數字當成選候選（比 macOS 更不符預期）；現以
`pressesBegan/Ended` 追蹤 Shift（左右鍵各自記錄、含生命週期重置）、依同偏好輸出；
附帶修復英文模式 Shift+字母恆小寫。
真硬體 E2E（模擬器＋Mac 鍵盤實測）：`a`＋空白→「對」＋聯想列 → Shift+1 →
「對!」（symbol 預設）與「對1」（digit 模式）皆實測通過，截圖存證於 iOS repo
`doc/evidence-20260908-shift-symbol.png`／`-digit.png`。
