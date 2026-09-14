# Prefs UI 實作報告（2026-09-14 Wave1）

> 來源：`docs/audits/20260914-prefs-ui-review.md`。9 個背景 subagents 全因 429 quota 失敗，
> 改由主線單幹實作。頂層 5 tabs 不動（維持 toolbar segmented tabs，不換 sidebar）。

## 做了什麼（檔 → 變更）

- `main.swift`：window 660×540 → 800×600；新增 View menu，Cmd+1..5 經
  `selectPrefsTab` notification 切 tab（MINIMAL 版 4 項、full 版 5 項，`#if` 對齊）。
- `ContentView.swift`：`TabView(selection:)+tag`＋越界 clamp；`minWidth/Height` 800×600，
  消除啟動即被裁。新增 `selectPrefsTab` extension。
- `InputTab.swift`：CIN 匯入成功後塌成一行狀態列（✓ liu.cin＋大小＋重新匯入），
  `refreshCinState()` onAppear＋匯入成功後更新；Pinned／History 包 `DisclosureGroup` 預設收起；
  spacing 16→24；toggleCard minHeight 100→`Typo.cardMinHeight`、desc 1→2 行；grid minimum 104→128。
- `SuggestionTab.swift`：`regionCard(tw/cn)` 搬到語料來源段下（屬 Corpus 策略）；
  General＋Pro 間加 `domainQuery` 搜尋框（有 query 顯示過濾快照、拖放停用）；
  layerCard 加左移／右移 contextMenu＋`accessibilityAction`（`moveLayer` 調 `saveStrategy`）；
  精簡安裝空態從整張圖文壓成一行 hint；pro chip 垂直 padding 5→8；grid minimum 104→128、
  cellHeight 100→88；hint 文案補「…」明示按鈕。
- `ContextBar.swift`：profile chip 加 `…` 明示 Menu（編輯／複製／刪除，與右鍵同功能）；
  chip 垂直 padding 5→8（好點中率，非 AA 修復——28px 原已 pass 2.2 SC 2.5.8）。
- `Typo.swift`：hint 14→13；新增 `sectionSpacing=24`、`cardMinHeight=88`。
- `SelectableCardView.swift`：預設 minHeight 90→88；desc 1→2 行。
- `DomainCardView.swift`：固定 100×100 → `minWidth:112/minHeight:88`；desc 1→2 行；
  選中描邊 1.5→2（深色對比）。
- `AppearanceTab.swift`：「字型」GroupBox（三條字級，toast step 4→2）＋「固定窗背景」GroupBox
  （透明度 step 0.05＋`fixedAlignment` segmented＋`fixedYOffset` Stepper——既有 keys 終於有 UI）；
  `fontRow` Slider＋Stepper 共用 binding＋combine accessibility；checker Canvas 抽 `CheckerPreview`；
  debug.log 按鈕常駐 disabled＋help；toggleCard 對齊新 tokens。
- `ShortcutTab.swift`：demoRow 四條可點填入表單（＋help＋plus.circle affordance）；
  TextEditor 加 `\n` placeholder overlay。
- `ContextProfileEditor.swift`：基本／輸入／聯想改 `Grid`（砍寫死 frame 寬）；
  詞庫加搜尋框（`filteredDomains`）；`validate()` 空名 inline 紅字；儲存擋錯。
- `HelpTab.swift`：版本／回報列＋搜尋框固定頂部（移出 ScrollView）；
  `guide()` 改 `DisclosureGroup`（`collapsedGuides` 記憶＋搜尋命中強制展開）；
  `section()` 搜尋過濾＋key 寬 160→180；`helpHits` helper。
- `WelcomeView.swift`：砍 `TabView(.automatic)`（macOS 空白頂欄來源）換 ZStack/if＋手刻 dots；
  補「略過」；第一頁 `detectCin()` 顯示 ✓ 狀態；`frame(460×340)` 改 min＋padding。
- `help.md`：33 行全文壓成 3 行 pointer（消除與 HelpTab 機刻指南的重複渲染；
  見下方 e2e 截圖證據）。
- `08-preferences.md:17`：三頁→四頁，對齊 code tag0..3，補登出再登入一項。

## e2e 證據

- `swiftc -typecheck`：full 版＋`-DMINIMAL` 版皆零錯誤。
- `yabomish.sh build`（arm64）：`YabomishIM.app`＋`YabomishPrefs.app` 皆 `[OK]`。
- `run_tests.sh`：138 passed, 0 failed。
- 實機截圖（新 build，Cmd+1..5 切換）：輸入（CIN 狀態列＋固定排序／查字歷史收起）、
  聯想（… 按鈕＋搜尋框＋用詞習慣在語料段下）、快捷碼（可點範例＋placeholder）、
  外觀（字型／固定窗背景兩組＋Stepper＋對齊／偏移）、關於（固定頂＋搜尋＋折疊 guide）。
  發現並修掉兩個視覺 bug：fontRow 無 label 寬導致 Slider 被 Stepper 擠到 30px；
  help.md 全文 markdown 與機刻指南重複渲染。

## advisory 處置

- 44×44：接受，原 AA-failure 撤回，chip 28px pass 2.2 SC 2.5.8；本輪只做 32px+ nicety。
- WelcomeView dots：接受，機制修正為砍 TabView（空白頂欄）換 ZStack；頁數以 code 4 頁為準改 doc。

## Wave2（未做）

1. 共用 `CandidatePreviewView`（Input demo vs Appearance demo 各刻一套，樣式不一致）。
2. Pinned／History 從 Input 搬「進階」tab（本輪先折疊）。
3. 選中填充 `accent.opacity(0.18)` 深色語義色；`SelectableCardView` 未選中 `.plain` focus ring。
4. Domain 拖放 `move()` 等價鍵盤路徑（本輪只做了 layer；domain grid 因 filteredBinding 快照需重排守衛）。
5. `proChipGrid` 分類標題搜尋連動；ContextBar `…` 與右鍵去重（保留兩者是刻意的發現性選擇）。
6. MINIMAL 版實機啟動驗證（本輪只 typecheck；CI 無 MINIMAL prefs artifact）。
