# 聯想預先反白開關（suggestPreselect）— 2026-09-09

> 接續兩個前案：`abd3287`（Space 不再代送第一候選）與 0.3.63 `e59ea50`（Enter 不再代選聯想詞）。
> 使用者回報原文：開啟聯想後第 0 候選預設反白，聊天軟體中打完字按 Enter 是要送訊息，不是選下一個詞，希望可關閉。

## 判定

前兩案已把「反白第 0 候選 → Enter／空白代送」的實質行為全部收掉，反白本身只剩視覺與
方向鍵導航起點兩個作用。因此不加「是否代送」的開關，直接把剩下的預先反白做成
**視覺偏好開關，預設關（維護者裁定：預設不要預反白）**：

- 關（預設）：聯想顯示不反白任何候選。數字鍵選詞不受影響（selKeys 本就與反白無關）；
  方向鍵從未反白狀態按任一方向，落在第 0 候選開始導航。
- 開：聯想列第 0 候選反白（0.3.63 前的視覺觀感）。

範圍僅限**純聯想顯示（組字已空）**。組字候選（VRSF／注音／拼音）一律反白第 0 候選，
不受此偏好影響——空白鍵送首選等組字語意依賴反白的一致性。

## 變更

1. **`Prefs.swift`**：新偏好 `suggestPreselect`（Bool，預設 false；Snapshot＋loadSnapshot＋遷移清單同步）。
   引擎層不讀取（面板層關切），`IMEPreferences` protocol 不動。
2. **`CandidatePanel.swift`**：`highlightIndex` 改為 `Int?`（nil = 不反白）；
   `show(...)` 新增 `preselectFirst: Bool = true`。VoiceOver 朗讀跳過未反白狀態；
   `moveUp/moveDown` 對 nil 落在第 0 候選；`pageStart` 以 0 計。
   渲染處 `candIdx == highlightIndex`（Int vs Int?）語意不變。
3. **`YabomishInputController.swift`**：
   - `showNewEngineCandidatePanel`：`preselectFirst = !composing.isEmpty || suggestPreselect`。
   - 注音／拼音 Enter 分支：`selectedCandidate()` 為 nil（純聯想＋預選關）時比照主路徑
     收提示、`return false` 把換行還給 app——拼音模式送字後會出聯想
     （`_commitText` 的 suggest 閘門只排除同音／注音），此分支原本會吞掉 Enter。
   - **順手修正**：純聯想顯示時 Space 輸出空白後提示窗滯留（a74334f 以來的既有行為）；
     現比照 Enter 收掉提示再 `return false`。
4. **`YabomishPrefs`**：`PrefsStore.suggestPreselect`＋InputTab「輸入功能」格
   「聯想預先反白」卡片（`#if !MINIMAL`，跟著聯想輸入主開關）。
   **順手修正**：Shift＋數字鍵區塊（未發行）引用 `#if !MINIMAL` 的
   `shiftDigitOutput` 但自身無 guard，`-DMINIMAL` 建置失敗；補上編譯旗標。

## 不變式

- 組字中任何按鍵行為完全不變（偏好只在 `composing.isEmpty` 路徑生效）。
- Enter／Space／Escape 在純聯想顯示時：收提示＋按鍵原意還給 app（三者行為對齊）。
- 數字鍵選聯想詞、Emoji 聯想位置、聯想層順序等既有功能不受影響。

## 驗證

- `Tests/run_tests.sh`：138 passed（含 Prefs.swift 編譯）。
- `Tests/test_horizontal_panel.swift` 新增 10 檢查：偏好 setter round-trip、panel API 預設反白
  （組字安全）、關閉後無反白＋`selectByKey` 仍可用＋方向鍵導航進入點。27 passed／1 failed——
  該失敗（vertical 版面斷言）在改動前 baseline 重現，屬測試環境既有問題
  （harness 寫 `UserDefaults.standard`、面板讀 suite）。
- 四目標編譯：IM full／IM MINIMAL／Prefs full／Prefs MINIMAL。
