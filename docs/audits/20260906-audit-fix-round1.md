# 20260906 盤點修復報告（Round 1）

> 範圍：2026-09-06 全面盤點後的第一輪修復。ralf 流程：三個分區修復 agent → 獨立驗證 → 對抗式審查（第一輪 FAIL）→ 修復 8 項 → 第二輪聚焦審查（PASS）→ E2E 安裝驗證。

## 修復清單

### 真實 Bug（使用者直接受害）

| # | 問題 | 修復 |
|---|------|------|
| 1 | **固定模式滑鼠點擊永遠送出第 1 個候選字**（`CandidatePanel.swift` mouseDown 首輪迭代即 return） | 逐段量測 attributed string 寬度建立命中矩形（`rebuildFixedHitRects`），點擊命中才送字、未命中不動作；文字被 85% 螢幕寬截斷時停用點擊選字（安全退化，僅留數字鍵） |
| 2 | **每個 IMK session 各建獨立 FreqTracker** — controller flush 的是從未收過資料的 static 實例，未滿 50 筆的字頻批次可能永不落盤，freq.json 跨裝置同步（deferredMerge）在 macOS 永不執行 | engine 建立處注入 controller 的 static `freqTracker`（`YabomishInputController.swift:350`）；新增 `startBackgroundTasks()` 於啟動時背景執行一次性 `deferredMerge()` |
| 3 | **`com.yabomish.reloadTables` 是死通知** — Prefs 存快捷碼/匯入字表後宣稱「即時重載」，IM 端無觀察者 | AppDelegate 註冊觀察者，執行 `reloadTable()`＋`CommaCommandRunner.reload()`＋`UserSnippets.reload()`（與 `,,RL` 同組） |
| 4 | **`,,RL` 說明文件宣稱可用但引擎從未實作**（打了回「未知命令」） | `_dispatchCommaCommand` 新增 `rl` 分支，重載三件組＋toast |
| 5 | **查字歷史 UI 顯示「,，ZH」全形逗號**，照畫面輸入無效 | `LookupHistorySection.swift` 兩處改 `,,` |
| 6 | **匯入 .cin 清錯快取檔**（`liu.cin.cache` 不存在，真正的編譯快取是 `liu.bin`）且 `reloadLocked()` 無新鮮度檢查 — 二次匯入永遠載舊表還回報成功 | InputTab 改清 `sharedDir/liu.bin`；`CINTable.ensureFreshCompiledBin()` 以 mtime 檢查（cin 比 bin 新就重編），IM 內建匯入路徑（CINImportCoordinator）同時受惠 |
| 7 | **CINTable 無鎖跨執行緒讀寫**（主執行緒 lookup vs global queue 預熱/reload）— 唯一可能直接 crash 的併發點 | `stateLock`（NSLock）＋`locked<T>()` helper 涵蓋全部公開成員；集合回傳為鎖內快取；每擊鍵僅取鎖 2–4 次 |
| 8 | **IMK 範圍以 `String.count` 當 UTF-16 offset** — emoji／非 BMP 候選字會錯位或刪半個 surrogate pair | `engineDidUpdateComposing/Commit/CommitPair/DeleteBack` 全改 `utf16.count` |

### 效能（打字手感）

| # | 問題 | 修復 |
|---|------|------|
| 9 | **prefsChanged 廣播風暴**：改個字級也同步重開所有 domain bins＋主執行緒同步重掃 freq.db | AppDelegate 以 DispatchWorkItem 去 0.5s 抖動；FreqTracker 觀察者同樣去抖＋`reloadPinned` 改 `bgQueue.async` |
| 10 | **啟動即主執行緒全量載入語料**（log 行觸碰 `WikiCorpus.shared.domainBinCount`） | 移除該 eager 觸碰，單例照原設計於 `activateServer` 背景預熱 |
| 11 | **CINTable 重載期間打字凍結**（鎖內編譯整份 .cin，秒級） | 編譯移至鎖外（`ensureFreshCompiledBin`），鎖內僅 mmap＋overlay 解析 |
| 12 | **ZhuyinLookup 首次注音擊鍵在主執行緒解析 3 份 JSON 且無鎖** | `ensureLoaded` 上鎖（once 語意）＋加入 activateServer 背景預熱清單 |
| 13 | **FreqTracker init（SQLite 開檔＋全量載入）落在首次按鍵** | `startBackgroundTasks()` 啟動時背景具體化 |

### Prefs App 品質

| # | 問題 | 修復 |
|---|------|------|
| 14 | **CSV 匯出無逃脫**（ShortcutTab 直字串串接，含逗號/引號即壞檔） | 共用 `Csv.swift` `csvEscape()`（RFC 4180：逗號/引號/CR/LF）；ShortcutTab 補 UTF-8 BOM |
| 15 | **卡片 builder 複製 7–8 份** | 抽成 `SelectableCardView`（參數化 iconText/checkmark/highlight/lineLimit/minHeight），8 個呼叫站收斂；順帶補齊 SuggestionTab 卡片無障礙標籤 |
| 16 | **DateFormatter 每列重建**（1000 列 → 1000 個） | static 快取 |
| 17 | **匯入字表寫 legacy 路徑**（`~/Library/YabomishIM/`）且無驗證、失敗靜默 | 改寫 IM 實際讀取的正規路徑（.cin → `sharedDir/liu.cin` 固定檔名；.txt → `tables/`）；%chardef 內容嗅探（前 64KB）；同目錄暫存＋`replaceItemAt` 原子替換（失敗不弄丟舊表）；成功/失敗 alert |
| 18 | **PrefsStore `UserDefaults(suiteName:)!` 強制解包** | `?? .standard` |
| 19 | **文件不一致**：WelcomeView 寫 `';`、HelpTab 寫 `,,ZH` | 查證 macOS 唯一入口是 `,,ZH`（`'`/`;` 皆直通送出）；三處文件對齊 |

### 建置流程

| # | 問題 | 修復 |
|---|------|------|
| 20 | **版本號讀到 CHANGELOG 頂端 `[Unreleased]` 產出字面 "Unreleased" 版本**（本日安裝即發生） | `yabomish.sh`×2＋`tools/release.sh` 跳過 Unreleased 取最新語意化版本；本次 build 已驗證為 `0.3.61.20260906.1945.5b15592` |
| 21 | **3 支現役 tools 腳本未版控**（`build_jingjing_v2.py` 等是 8/27 重建 terms_jingjing.bin 的唯一依據） | 已 commit（`95498fe`） |
| 22 | `site/.astro/` 未忽略 | .gitignore 補上 |

## 驗證

- **編譯矩陣**：IM full／IM MINIMAL／Prefs／Prefs MINIMAL — 四路 0 error 0 warning（修復前、第一輪審查後、第二輪審查後共三輪全跑）
- **既有測試**：`YabomishIM/Tests/run_tests.sh` — **138 passed, 0 failed**（覆蓋 InputEngine／CINTable／FreqTracker 改動）
- **對抗式審查**：第一輪 FAIL（C1 匯入快取失效＋M1 鎖內凍結＋M2 截斷命中）→ 全數修復 → 第二輪聚焦審查 6/6 PASS
- **鎖順序静态驗證**：engineLock → CINTable.stateLock 單向；CINTable 為葉類無回呼；ZhuyinLookup.loadLock 無巢狀
- **E2E**：腳本重編（版本號正確）→ 安裝至 `/Library/Input Methods` → 輸入法程序啟動（完整版資源＋字表就緒）→ Prefs app 更新

## 已知不修（本輪，低風險備查）

- `,,RL` 持 engine 鎖執行秒級重編譯 — 手動罕發指令，可接受；改善方向：丟背景 queue 先回 toast
- 命中矩形量測（逐段 `.size()` 累加）與 `intrinsicContentSize` 可能有數 px 微差 — fail-safe 方向（只失去點選、不誤送字）
- `fallbackFixed` 模式點擊走游標分支（stackView 隱藏）→ 點擊無效 — 既有行為
- `engineDidDeleteBack` 讀 `engine._lastCommittedText` 未持 engine 鎖 — 目前 delegate 全在 engine 鎖內同執行緒回呼，安全
- 首次 prefsChanged 可能在主執行緒首次建立 WikiCorpus — 實務上 activateServer 預熱先發生

## 後續改進 Backlog（依優先序）

1. **偏好快照**：熱路徑每擊鍵讀 UserDefaults 6–10 次 → 啟動＋prefsChanged 時快取成 struct（手感 CP 值最高）
2. **CI**：`.github/workflows/` 只有網站部署；`run_tests.sh` 掛 macOS runner＋四路編譯矩陣
3. **repo 瘦身**：pack 429 MiB（NAER CSV／客家 ODS 等原始語料入庫）→ LFS 或 Release 附件
4. **.bin 可重現性**：corpus zip 無產生腳本、`DataDownloader` 寫死 `v0.3.59` URL＋SHA-256
5. **送字路徑聯想非同步化**：`_commitText` 鎖內同步跑完整聯想查詢 → 非同步＋debounce 100ms
6. **死碼清理**：`PhraseLookup` Layer2/3、`UserPhrases`、`ClipboardProcessor` HTML→Markdown（~250 行）、chengyu.bin 恆載入但查詢無人呼叫、`useNewEngine`/`zhuyinReverseLookup` 無效開關
7. **重複統一**：toast builder ×2、候選導航 ×3、拼音 tone ×2、backspace ×2、`selectCandidate` 兩份行為已分歧
8. **DebugLog**：`@autoclosure`＋`os.Logger`＋輪替鎖
9. **杂項**：`deactivateServer` 自動送第一候選（改 discard？）、`engineDidPasteText` 覆寫剪貼簿後還原、`doc`/`docs`/`doct` 三目錄整併、wildcard 查詢前綴掃描、`InputEngine` actor 化

## 修改檔案

- IM：`AppDelegate` `CINTable` `CandidatePanel` `FreqTracker` `Shared/InputEngine` `YabomishInputController` `ZhuyinLookup`
- Prefs：`AppearanceTab` `Csv.swift`(新) `InputTab` `LookupHistorySection` `PrefsStore` `SelectableCardView.swift`(新) `ShortcutTab` `SuggestionTab` `WelcomeView`
- 建置：`yabomish.sh` `tools/release.sh` `.gitignore`
