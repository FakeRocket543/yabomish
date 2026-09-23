# REPORT — macOS↔iOS↔Android 功能追平審計（2026-09-24）

> 問題：iOS／Android 都追平 macOS 版了嗎？
> 答案：**核心輸入與聯想引擎：是。周邊功能：本輪補完後是，剩餘差異全為平台限制或等價模型，詳下。**

## 三方差異矩陣（審計後）

### 指令集（`,,`）

| 指令 | macOS | iOS | Android | 備註 |
|------|-------|-----|---------|------|
| T/S/SP/SL/TS/ST/J 模式 | ✅ | ✅ | ✅ | |
| ZH 注音 / TO 同音 / PYS/PYT 拼音 | ✅ | ✅ | ✅ | |
| PIN/UNPINx 固定排序 | ✅ | ✅ | ✅ | |
| V/VT/VS 剪貼簿 | ✅ | ✅（膠囊＋UIPasteControl 雙軌，fcbc070） | ✅ | |
| SG/RS/RL/C/H | ✅ | ✅ | ✅ | |
| LH/RH 查字歷史 | ✅ | ✅ | ✅ **本輪補上**（FreqTracker lookup_history＋指令＋zh/to/pys/pyt 四路記錄） | |
| X snippets | ✅ | ✅（CommaCommandRunner type:text） | ✅（commands.json v2，6a06457） | |
| open（app/bundle ID） | ✅ | ❌ 放掉：鍵盤 extension 無法拉起任意 app（沙盒） | ❌ 放掉：同上 | 平台限制 |
| B/F app 導航（AppSwitchTracker） | ✅ | ❌ 放掉：NSWorkspace 不存在於 iOS | ❌ 放掉：Android 需 UsageStats 特權，不符零權限原則 | 平台限制 |
| P 開偏好設定 | ✅ | ❌ 放掉：同 open | ❌ 放掉 | 平台限制 |

### 聯想引擎（送字後）

| 層 | macOS | iOS | Android |
|----|-------|-----|---------|
| L0 使用者自訂詞組 | ✅ | ✅ | ✅ **本輪補上**（SuggestionEngine pool0，原本 UserPhrases.suggest 寫了沒接） |
| 萌典詞組 phrases | ✅ | ✅ | ✅ |
| 詞級 n-gram / word_news | ✅ | ✅（word_news 併入 PhraseSuggest 詞頻） | ✅ |
| 領域詞庫 | ✅ 36 域＋拖曳排序 | ✅ 22 域（DomainMerger 合併式；本輪＋**domain_jingjing 經經**——資料本在 bundle，domainKeys 漏列） | ✅ 36 域 |
| 經經 jingjing-ti 獨立池 | ✅ poolJJ | ✅（經 domain_jingjing 域開關；合併式架構，非獨立池——能力等價） | ✅ poolJJ |
| 成語 chengyu | ✅ | ✅（chengyuFirst 排序） | ✅ **本輪補上**（poolCY＋chengyuSuggest 開關＋chengyuFirst 接活——原 pref 與 suggestChengyu 都是死碼） |
| 字級 bigram/trigram | ✅ | ✅ | ✅ |
| Emoji（emojiFirst/emojiSuggest） | ✅ | ✅ | ✅（恆尾端；emojiFirst 無——等價模型差異，接受） |
| Region 兩岸降權 | ✅ | ✅ | ✅ |
| 策略開關 | suggestStrategy 三層＋suggestEnabled | charSuggest/wordSuggest/chengyuSuggest/chengyuFirst 逐層開關（等價模型） | suggestStrategy＋suggestEnabled＋charSuggest/wordSuggest＋本輪 chengyuSuggest/chengyuFirst |

### 輸入核心

| 功能 | macOS | iOS | Android |
|------|-------|-----|---------|
| 破音字兩層同音選取 | ✅ | ✅（721562f） | ✅ **本輪移植**（lookup 恆回全部讀音群＋兩層狀態機＋上屏路徑封死，8bf95e0） |
| homophoneMultiReading 混排 | ✅ | ✅ | ✅ **本輪接活**（原 pref 死 key） |
| homophoneAutoExit | ✅ | ✅ | ✅ |
| PIN 模式 | ✅ | ✅ | ✅ |
| 滿碼自動送字 autoCommit | ✅ | ✅ | ✅ |
| 萬用碼/鄰鍵容錯 | ✅ | ✅ | ✅ |
| 注音大千／拼音查碼 | ✅ | ✅ | ✅ |
| commands.json v2 type:text | ✅ | ✅ | ✅ |

### 鍵盤排法／UI

| 項目 | macOS | iOS | Android |
|------|-------|-----|---------|
| 四排 QWERTY（符1.35／英，空。↵） | —（候選窗） | ✅ | ✅ |
| Numpad 3×4 T9＋數字欄位自動切換 | N/A | ✅ | ✅ **本輪移植** |
| 空白鍵五向手勢＋開關 | N/A | ✅ keyGestures | ✅ **本輪補上開關**（手勢本有，閘門新增） |
| 高度調整 | N/A | ✅ 拖曳＋滑桿 | ✅ 滑桿 |
| 長按字母出數字 | N/A | ✅ | ✅ |
| 觸覺分級（按鍵/送字/聯想 0-3） | N/A | ✅ | ✅ |
| 無效鍵變暗／按鍵外框 | N/A | ✅ | ✅ |

### 偏好 key 三方差（審計後殘留，皆屬平台模型差異）

- macOS 獨有：suggestPreselect、外觀細項（fixedWindow 系、panelPosition、toastFontSize）、corpusVariant/下載器、syncFolder、ContextProfile 語境系 —— CandidatePanel／桌面工作流特有
- iOS 獨有：autoCapitalize、enableSound、keyGestures（Android 本輪補）、chengyuFirst（Android 本輪接活）
- Android 獨有：suggestStrategy/wordCorpus/wikiCorpus（策略模型差異，能力等價）

## 本輪變更

### Android（commit 8bf95e0 之後續）
- `FreqTracker.kt`：`lookup_history` 表＋`LookupEntry`＋`recordLookup/recentLookups/clearLookups`（cap 1000）
- `InputEngine.kt`：`,,LH/,,RH` 指令＋HELP_TEXT；zh/to/pys/pyt 四路 `recordLookup`；同音 stage2 commit 前捕 base
- `SuggestionEngine.kt`：pool0（UserPhrases）＋poolCY（成語，chengyuSuggest gate）＋chengyuFirst 排序
- `YabomishPrefs.kt`：`chengyuSuggest`（預設開）、`keyGestures`（預設開）
- `KeyboardScreen.kt`：手勢閘門；`SettingsActivity.kt`：成語聯想／成語優先／空白鍵手勢三開關

### iOS
- `WikiCorpus.swift`：`domainKeys` 補 `("domain_jingjing","terms_jingjing","經經")` —— merge／設定 UI／全選自動接上，terms_jingjing.bin 原本就在 bundle

## 驗證

- Android：`compileDebugKotlin` 0 錯；`testDebugUnitTest` **34 tests, 0 failed**
- iOS：`xcodebuild build -scheme YabomishKeyboard`（結果見對話尾段）
- 三 repo 差異以 grep 指令表／prefs key／WikiCorpus+SuggestionEngine 函式面逐項比對

## 放掉清單（平台限制，永不上移動端）

`,,B/,,F`（NSWorkspace/UsageStats）、`,,P`、commands.json `open` 型、固定候選窗外觀系、corpus 下載器（移動端全語料離線內建）、ContextProfile 語境系（桌面工作流）

## 後續建議

1. iOS 若要 36 域全開，把 Android 的 `proDomainKeys` 清單對拷（剩 14 域的 bin 需自 macOS Resources 複製進 iOS bundle，體積 +N MB，60MB extension 上限內可行但需實測）
2. Android emoji 層可補 emojiFirst 排序偏好（小）
3. 真機驗證：iOS 經經域開關→聯想出「cue到」類詞；Android ,,LH 清單呈現
