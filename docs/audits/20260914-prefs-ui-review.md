# YabomishPrefs macOS 偏好設定 UI 審查（2026-09-14）

> 範圍：`YabomishPrefs/Sources`（ContentView / InputTab / SuggestionTab / ShortcutTab /
> AppearanceTab / HelpTab / WelcomeView / PinnedOrderSection / LookupHistorySection /
> ContextBar / ContextProfileEditor / SelectableCardView / DomainCardView / Typo / PrefsStore /
> main.swift）＋ `site/public/images/prefs-*.webp` 實機截圖 ＋ `site/src/content/chapters/08-preferences.md`。
> 標準：macOS HIG（toolbar-style tab picker、system controls、form spacing），保留現有頂部
> segmented tabs，不換 Web 式 sidebar。

## 前提更正（advisory 已採納）

- **Target size 不是 AA 缺陷**：WCAG 2.1 AA 無 target-size 條款；2.2 AA SC 2.5.8 為 24×24 CSS px。
  `ContextBar.swift:31` chip padding 10×5、高度約 28px —— **pass**。原「44×44 ✗」撤回，
  改列 usability nicety（拉到 32px+ 好點中率即可）。
- **WelcomeView 機制**：`WelcomeView.swift:9,51` 是 `TabView(selection:)+.tabViewStyle(.automatic)`、
  無 `tabItem`、無 `.page` —— macOS 下不會出現 iOS 式 dots，只剩一條空白頂欄。
  原「系統 dots + 手刻 Circles 重複」不成立；修法是砍 `TabView` 換 `ZStack`/`if page==` 切頁。
- **頁數出入**：code 4 頁（`tag(0..3)`：匯入字表／登出再登入／加入輸入方式／常用快捷鍵），
  但 `08-preferences.md:17` 寫「三頁引導流程」。兩邊對齊其一。

## P0：先修

### P0-1 ContentView 視窗尺寸打架＋無鍵盤切 tab
- `main.swift:44` window 開 660×540，`ContentView.swift:35` 卻 `minWidth:760 minHeight:520` ——
  啟動即被裁、橫向 scrollbar（`prefs-*.webp` 皆 760+ 寬可證）。
- 修：window contentRect 與 content min 統一 800×600 起跳；加 `Cmd+1..5` 切 tab
 （`@State selection` + `.tag()`，或 NSMenu 層加快捷鍵）。
- 約束：本輪**不增減頂層 tab 數量**（`#if !MINIMAL` 分支保持），只修尺寸＋快捷鍵。

### P0-2 InputTab 一頁 5 件事（`InputTab.swift:46-145`）
- CIN 匯入 GroupBox 置頂正確（onboarding），但匯入成功後永遠佔整張卡，把 8 個 toggle 擠出 fold
 （`prefs-input.webp` 一路滾到底可證）。
- `PinnedOrderSection`（查詢＋候選＋固定順序三欄）與 `LookupHistorySection`
  （`maxHeight:264` 內嵌 ScrollView、`LookupHistorySection.swift:86`）是獨立 organism，
  寄生在輸入頁使單頁含：匯入＋選字窗＋demo＋8 toggle＋Shift+數字＋固定排序＋查字歷史。
- 修：匯入成功後 GroupBox 塌成一行狀態列（✓ 已匯入 liu.cin＋大小＋重新匯入）；
  Pinned / History 包 `DisclosureGroup`（預設收起）或搬「進階」。本輪選前者，避免跨 tab 搬移衝突。

### P0-3 SuggestionTab 一頁 6 段（`SuggestionTab.swift:51-159`）
- ContextBar＋用詞習慣＋層順序＋語料來源＋一般詞庫 12 卡＋專業詞典 28 chip，
  `prefs-suggest-top/bottom/pro-domains.webp` 三張才截完。
- `proChipGrid` 預設收起正確，但 badge `n/count`（`SuggestionTab.swift:142-148`）發現率低。
- 修：本輪不拆頂層 tab；頁內重排 —— `regionCard(tw/cn)`（邏輯屬 Corpus 策略）從 Context 下方
  搬到語料來源段；General＋Pro 之間加搜尋框；Pro 保持收起。
- 拖放（`:106` layer、` :236` domain 的 `dropDestination`＋背景 `GeometryReader` 量寬 hack）
  **只有拖放一條路**：鍵盤動不了，VoiceOver 過不了；`ContextBar.swift:37` 編輯／複製／刪除只藏右鍵。
  修：卡片加 grip affordance＋「左移／右移」`contextMenu`＋`accessibilityAction`；
  ContextBar 右鍵功能同時給 `...` 明示按鈕。`.draggable` 保留當加速器。

## P1：卡片系統一統＋Appearance 重整

### P1-1 兩套卡片三種高
- `SelectableCardView.swift:18` `minHeight:90` vs Input 私刻 `toggleCard` 100
 （`InputTab.swift:252`）vs `DomainCardView.swift:33` 寫死 100×100。
- 結果：`prefs-suggest-bottom.webp` 一般詞庫 desc 全截（「教育部閩南語…」「台式中英夾…」`lineLimit(1)`）。
- 修：統一 minHeight 88；desc `lineLimit(1→2)`；`adaptive(minimum:104→128)`（760 寬下 6–7 欄太密）；
  `DomainCardView:33` 固定框改同一 token。選中填充 `accent.opacity(0.18)` 深色下對比弱，描邊加重
  或改系統 `selection` 語義色。

### P1-2 AppearanceTab Slider 分組錯（`AppearanceTab.swift:50-71`，見 `prefs-appearance.webp`）
- 字級三條＋`fixedAlpha 0.3...1.0` 混一起全屏長滑桿；label `frame(width:80)`＋value `width:40` 本地化一換就斷。
- 修：HIG `Form`/`LabeledContent` 重排 —— 「字型」一組、「固定窗背景」一組
  （透明度＋對齊＋Y offset；後兩者 `PrefsStore` 有值、`fixedAlignment`/`fixedYOffset`，UI 無面）；
  `toastFontSize step:4→2`；Slider 旁加 Stepper 顧鍵盤用戶；
  `:109-121` checker `Canvas` 寫在 body 每幀重算，抽獨立 `PreviewView`。
- `debugMode` 開才出現的「打開 debug.log」（`:155-163`）是隱藏 affordance，改常駐 disabled＋hint。

### P1-3 Typo 層級塌陷（`Typo.swift:13-15`）
- `hint=14`＝`body=14`，說明退不下去；`cardDesc 13` 只差 1pt。
- 修：hint 13＋一律 `.secondary`；段間距 16→24（各 tab `VStack spacing:16` 自改）；
  `SectionDivider` 上下 6 太擠。

## P2：各頁快贏

- **預覽重複**：Input 選字窗 demo（1蝦2米3蟹，`InputTab.swift:88-108`）與 Appearance cursor/fixed demo
  （`AppearanceTab.swift:74-135`）各刻一套，樣式不一致（`ultraThinMaterial` vs
  `windowBackgroundColor.opacity(alpha)`）。合一為共用 `CandidatePreviewView`。
- **ShortcutTab demoRow 靜態最可惜**（`ShortcutTab.swift:64-70`，見 `prefs-shortcuts.webp`）：
  `agpt/amtg/acmd/asig` 四條加「點一下填入新增表單」。`addSection` 的 `TextEditor(60pt)` 加
  placeholder＋`\n` 提示；`codeStatus` 即時校驗已好、留著。
- **ContextProfileEditor sheet 420 寬**（`ContextProfileEditor.swift:33-111`）：
  mode/region/strategy/corpus 已是 `Picker`（比之前說的好），但全擠 `GroupBox`＋寫死 frame
  （名稱 120／圖示 50／mode 100）；詞庫 40 個 checkbox (`:83-102`，`height:180` ScrollView) 無搜尋。
  修：拿掉寫死寬度，詞庫加搜尋框，`validateNew` 錯誤改 inline 提示。
- **HelpTab 一個 ScrollView 攤平**（`HelpTab.swift:34-171`，`prefs-about.webp` 最長頁）：
  加搜尋框，`guide()` 改 `DisclosureGroup`，版本／回報列固定頂部；
  授權表 key `width:160`（`:267`）碰到 `,,VT／,,VS` 壓線，放寬到 180。
- **WelcomeView**：砍 `TabView` 換 `ZStack`/`if`＋保留手刻 dots＋補「略過」；
  第一頁偵測 liu.cin 是否存在（存在即顯示狀態）；`frame(460×340)` 固定尺寸拿掉；
  頁數與 `08-preferences.md:17` 對齊（三或四擇一；留登出再登入就改 doc 為四頁）。

## 建議 IA（維持 5 tabs，不動頂層）

輸入（核心開關＋選字窗＋Shift+數字）／聯想與詞庫（頁內重排＋搜尋）／快捷碼
（可點範例＋placeholder）／外觀（Form 分組＋共用預覽）／關於（搜尋＋折疊）。
Pinned＋History 本輪先折疊，下一輪再搬「進階」。每頁 ≤4 個 H2；
現在 `h2 17 bold` 滿版都是標題等於沒標題。
