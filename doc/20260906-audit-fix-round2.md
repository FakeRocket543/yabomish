# 20260906 盤點修復報告（Round 2 — 效能與去重）

> 接續 [round 1](20260906-audit-fix-round1.md)。本輪目標取 backlog 前段：偏好快照（熱路徑 UserDefaults 讀取）、重複統一、死碼清理。流程：三 agent 分區修復（D/E/F）→ 四路編譯＋138 tests → 對抗式審查（**PASS**，3 個 MINOR 全數修復）→ E2E 安裝。

## 修復內容

### 1. 偏好快照（Agent D — `Prefs.swift`）

熱路徑每擊鍵 6–10 次 UserDefaults 讀取 → 內部 `Snapshot` struct（27 個純量偏好）＋`NSLock` 保護：
- getter 讀快照（uncontended NSLock 約數十 ns）；setter 先寫 defaults 再刷新快照（同行程變更如 `,,SG` 即刻生效）
- 跨行程：`prefsChangedObserver` 以 `static let` lazy 初始化保證只註冊一次，Prefs app 寫入廣播後刷新
- 審查修補：`refreshSnapshot()` 讀取與替換同在鎖內，並發 refresh 序列化（消除撕裂讀覆蓋競爭）
- `domainEnabled` 等低頻存取維持直讀 defaults；`migrateLegacyPrefs` raw 寫入後補刷新

### 2. 重複統一（Agent E — controller＋engine，行為保持）

| 標的 | 處置 |
|---|---|
| toast builder ×2（切入提示/字根提示） | 合併為 `showToast(_:style:duration:slot:)`；codeHint 的 `midY+60` 底邊座標語意以 `.fixedOffset` 精確重現 |
| 候選導航 ×3 | `navigateCandidates` 回傳 Bool — 發現三塊的差異在未匹配時的落穿行為（第一處續走後續處理、另兩處續查 keycode 48/36），以回傳值保留 |
| 「送首選或跳離」×4 | `commitOrEscapeComposing`；shift+數字變體獨有 else 分支保留原處 |
| `firstIndex(of:)` 反查 ×7 | `candidateIndex(of:)`（原本就都是 `?? 0`） |
| 拼音聲調 ×2 | 兩份逐字相同，`handlePinyinTone` 改為薄包裝呼叫 impl |
| backspace ×2 | 死掉的 `_handleBackspaceImpl` 直接刪除（缺 Pin 分支的舊版），保留唯一活實作 |
| **`selectCandidate` 行為分歧** | 死版 `_selectCandidateImpl`（唯一呼叫端是死掉的 `selectByDigit`）整個刪除 — 分歧自然消失，活版一字未動 |

### 3. 死碼清理（Agent F — Shared；每項先 grep 全 repo 驗證）

**刪除**（淨 −947 行 / +445 行）：
- `PhraseLookup.swift` 整檔（唯一引用是預熱行，隨之移除；省 SQLite 4MB 頁快取＋開檔 I/O）
- `UserPhrases.swift` 整檔（零引用）
- `DomainMerger.swift` 整檔（零引用）
- `ClipboardProcessor` 的 `htmlToMarkdown`＋私有輔助（−277 行；`plainText`/繁簡轉換保留）
- `WikiCorpus.suggestChengyu`/`loadChengyu`/cy* 成員（零呼叫端；省 chengyu.bin 重複映射 ~1.1MB — 網域詞庫載入路徑不受影響）＋ `suggestWordBigram` 包裝
- `MemoryBudget.trimIfNeeded`；連帶 `CINTable.releaseOptionalCaches`（唯一呼叫端消失）
- 引擎死 API：`undoLastLetter`（＋`_snap*` 狀態）、`selectByDigit`、`InputEngine.validNextKeys()`、`shortestCodeHint`、`scheduleBackgroundTasks`
- controller 死變數：`lastDeactivateTime`、`lastCommittedLength`

**查證後保留**（審計誤報）：
- `FreqTracker.topBigrams`/`bigramBoost` — 測試使用中；`saveIfNeeded` — `InputEngine:959` 使用中
- `ContextProfile.createDefaults` — Prefs app 經 **symlink** 共用此檔（`YabomishPrefs/Sources/ContextProfile.swift` → `YabomishIM/Sources/Shared/`），ContextBar 呼叫中
- `wb*`（word-bigram 資料）— `suggestWordNgram` 活躍使用，非死碼

**附帶清理**：Prefs app「注音反查」無效開關（IM 從未讀取此偏好，`,,ZH` 恆可用）＋`useNewEngine`/`zhuyinReverseLookup`/`menuBarLabel` 三端死屬性（key 字串保留在遷移清單）；README 檔案樹與 `run_tests.sh` EXCLUDE 過期條目。

**selkey cap 查證**：寫入端 10／讀取端 20 — 讀取端為防禦性寬鬆（編譯器永不寫超過 10），現行 .bin 不可能觸發差異，不改。

## 驗證

- 編譯矩陣：IM full／IM MINIMAL／Prefs／Prefs MINIMAL — 0 error 0 warning（agent 自驗＋P2 獨立重跑＋MINOR 修補後三輪全綠）
- `run_tests.sh`：**138 passed, 0 failed**（行為保持 oracle）
- 對抗式審查：快照 27 個預設值逐一比對一致；toast 像素等價；導航落穿語意保持；刪除符號零殘留；MINIMAL 與 symlink 編譯集確認
- E2E：腳本重編 → 安裝 → 輸入法啟動（pid 8190）→ Prefs app 更新

## 後續 Backlog（滾動更新）

1. **CI**：`run_tests.sh`＋四路編譯掛 GitHub Actions（macOS runner）— 待你決定 github 使用時機
2. **repo 瘦身**：429MB pack → LFS（需你決策，牽涉歷史改寫）
3. **bin 可重現性**：corpus zip 產生腳本＋`DataDownloader` 寫死 `v0.3.59` URL/SHA 改設定檔
4. **送字聯想非同步化**：`_commitText` 鎖內同步聯想 → 非同步＋debounce（行為變更風險，需規劃）
5. `deactivateServer` 自動送第一候選 vs discard（行為決策）；`engineDidPasteText` 剪貼簿還原
6. `DebugLog` 改 `@autoclosure`＋`os.Logger`；wildcard 查詢前綴掃描；`InputEngine` actor 化（大工程）
7. `doc`/`docs`/`doct` 三文件目錄整併
