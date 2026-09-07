# 20260906 盤點修復報告（Round 3 — repo 瘦身、行為決策、聯想實驗）

> 接續 [round 2](20260906-audit-fix-round2.md)。本輪處理 backlog 中需要使用者決策的三項：① LFS repo 瘦身、④ `deactivateServer` 行為決策、③ 聯想非同步化（獨立實驗分支）。推送僅 origin（git.lcn.tw），github remote 未動。

## ① Git LFS 瘦身

**測量**：pack 429MB 的元凶是歷史裡的 `.bin`（911MB／289 個歷史版本）＋`.csv` 128MB＋`.parquet` 66MB＋`.ods`/`.tsv` 34MB。`.bin` 雖早已停止追蹤，**歷史 blob 仍在 pack 中**。

**執行**：
1. 全量備份：`/tmp/yabomish-pre-lfs-backup.bundle`（431MB，舊 main = `a5a7455`，可隨時 `git clone` 救回）
2. `git lfs migrate import --everything --include="*.bin,*.csv,*.ods,*.tsv,*.parquet"` — 343 個 commit 全改寫、387 個現役檔轉 LFS 指針＋物件
3. `git lfs checkout` 還原工作樹真實內容（指針殘留 0）
4. 清掉 pin 舊物件的 refs（`refs/remotes/github/*` stale、已併入的 `pr13`）
5. Force push origin（main＋全部 tags，LFS 物件隨 push 上傳；git.lcn.tw 為 Gitea，支援 LFS）

**效果**：新 clone 只取現役資料（~150MB LFS 物件）；本機舊歷史 1.1GB 物件在 refs 翻轉後可 gc 回收。⚠️ 注意：此操作改寫全部歷史 hash，**其他機器的 clone 需重新 clone**（或跟隨 force push），舊 bundle 備份保留於 /tmp。

## ④ deactivateServer 行為決策：改 discard

**舊行為**：切換視窗／輸入法時，若組字區有候選，以 `handleSpace()` **代送第一候選字** — 未經使用者確認的字憑空落入底文。
**新行為**：一律 `handleEscape()` 丟棄（macOS 內建注音等多數 IM 慣例）。注音／拼音模式退出與清 marked text 路徑不變；`engineClient` 本就由 `activateServer` 設定，deactivate 端的賦值是死碼一併移除。
驗證：IM full／min 編譯＋138 tests 全過。commit `abd3287`。

## ③ 聯想非同步化 — 獨立實驗分支（未合併）

分支 **`experiment/async-suggest`**（自 main `abd3287`，commit `e86ad3b`）。

**問題**：`_commitText` 在 engine 鎖內、主執行緒同步執行 `suggestionEngine.suggest(...)`（WBMM 掃所有啟用 domain bins＋ngram＋trigram＋bigram＋emoji）— 快打時吃擊鍵間隙。

**實作**：
- 可注入 `SuggestionExecutor`：正式環境走背景 queue；測試注入 `{ $0() }` 同步 — **138 tests 零改動全過**
- `_suggestionGeneration` 世代計數：commit／escape 遞增，遞送前於鎖內複檢，過期結果靜默丟棄；遞送恆回主執行緒
- **附帶修掉既有併發缺陷**：查證發現 WikiCorpus 的資料（domainBins／nerData／jjData 等）**完全沒有同步** — lazy init 在 global queue、reloadDomains 在主執行緒去抖，本就是競態。新增 `NSRecursiveLock` 涵蓋全部 13 個公開讀寫入口（遞迴鎖因內部互呼；鎖序 engine→corpus 單向，無 ABBA）

**已知取捨**：suggest 在途期間持 corpus 鎖，主執行緒的 corpus 讀取（domain 策略）會短暫等鎖；`,,SG` 關閉瞬間已派發查詢仍可能遞送一次。

**建議**：方向可行、正確性基礎完備，但 **先別合併** — 需 (a) 真實打字體感評估（背景化收益 vs corpus 鎖競爭）、(b) Thread Sanitizer／Instruments 跑一輪真實輸入驗證鎖覆蓋、(c) 通過後考慮 WikiCorpus 改 serial queue＋snapshot 消除等鎖。

## 驗證彙整

| 項目 | 結果 |
|---|---|
| IM full／min＋Prefs full／min 編譯 | 0 error 0 warning |
| `run_tests.sh` | 138 passed, 0 failed（item 4 與實驗分支各自驗證） |
| LFS 遷移 | 343 commits 改寫、387 檔轉 LFS、指針殘留 0 |
| 實驗分支 | `git diff main --stat` 僅 InputEngine＋WikiCorpus（WikiCorpus 為 thread-safety 必要偏差） |

## 下一輪 Backlog（滾動）

1. **實驗驗收**：真實打字評估 experiment/async-suggest → 決定合併或迭代（serial queue＋snapshot 版 WikiCorpus）
2. **CI**：等 github 啟用時掛 `run_tests.sh`＋四路編譯矩陣
3. **bin 可重現性**：corpus zip 產生腳本＋DataDownloader 版本設定檔
4. `engineDidPasteText` 剪貼簿還原；DebugLog `@autoclosure`；`doc`/`docs`/`doct` 整併
