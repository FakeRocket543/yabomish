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

**除錯插曲 — Gitea href port bug＋nginx body 限制（未完項）**：git push 卡死在上傳階段（0 位元組、無進度）數十分鐘。逐層排查：
1. LFS batch API 以 curl 實測 0.7 秒回應 200（伺服器與認證正常）→ 檢查 batch 回應發現 **upload href 是 `https://git.lcn.tw/...`，少了 `:33333`** — Gitea 的 `ROOT_URL` 與實際 listen port 不一致，git-lfs 拿錯誤 href 對 443 上傳（該 port 黑洞、60 秒逾時 0 位元組），永遠卡住。
2. **繞道手動上傳 LFS**：`/tmp/lfs_upload.py` 對 batch API 取憑證、修正 port 後 4 路並行 curl PUT — **689 個物件中 470 個成功（全部 ≤1MB）**；219 個（978MB，含 tip 現役 13 個 1–5.8MB 大檔）被 **nginx `client_max_body_size 1m`** 以 413 拒絕（實測：900KB 過、2.5MB 413）。
3. git 資料推送同受 1m 限制：tag／小封包 commit 可過（已推 94/345＋全部 tags），卡在需重傳 ≥1MB 非 LFS blob 的 commit（origin 端已 gc 掉歷史中曾被刪除的大 blob，如 trigram_suggest.json 5.4MB；其餘為 region txt／word_bigram.json／AppIcon.icns 等現役合法檔）。

**需伺服器端（git.lcn.tw）兩處修正後即可一次完成**：
- nginx vhost 加 `client_max_body_size 100m;`（git smart-http 與 LFS PUT 共用此限制）
- Gitea `ROOT_URL` 補上 `:33333`（根治 LFS href；clone／pull 新機器目前同樣會踩坑）
修正後執行：`/tmp/lfs_upload.py .git`（補 219 個 LFS 物件）→ `/tmp/incremental_push.sh`（續推剩餘 commit）→ `git push origin experiment/async-suggest`。

**效果（本機已完成）**：歷史已改寫、工作樹真實內容還原（指針殘留 0）；⚠️ 歷史 hash 全變，其他機器需重新 clone；遷移前備份 bundle 保留於 `/tmp/yabomish-pre-lfs-backup.bundle`（431MB，含完整舊歷史）。

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
| LFS 遷移 | 343 commits 改寫、387 檔轉 LFS、指針殘留 0；LFS 物件 470/689 已上傳（伺服器 nginx 1m 限制擋下 219 個 >1MB 物件） |
| 實驗分支 | `git diff main --stat` 僅 InputEngine＋WikiCorpus（WikiCorpus 為 thread-safety 必要偏差） |

## 下一輪 Backlog（滾動）

1. **實驗驗收**：真實打字評估 experiment/async-suggest → 決定合併或迭代（serial queue＋snapshot 版 WikiCorpus）
2. **CI**：等 github 啟用時掛 `run_tests.sh`＋四路編譯矩陣
3. **bin 可重現性**：corpus zip 產生腳本＋DataDownloader 版本設定檔
4. `engineDidPasteText` 剪貼簿還原；DebugLog `@autoclosure`；`doc`/`docs`/`doct` 整併
