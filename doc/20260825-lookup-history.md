# 查字歷史（Lookup History）設計 — 2026-08-25

## 目標

用注音反查（`,,ZH`／`';`）、同音字（`,,TO`）、拼音查碼（`,,PYS`／`,,PYT`）查過並選字送出時，把該次查字記錄在輸入法本體（freq.db），之後可用 `,,LH` 檢視、`,,RH` 清除。實際用途：這份清單就是「不會拆碼的字」，可直接當弱點字複習素材。

## 非目標（v1 不做）

- 候選排序加權（查過的字 boost）— 需要排序實驗，另開議題。
- YabomishPrefs 查字歷史頁 — `,,LH` 已可檢視；等有模糊搜尋/統計需求再做 UI。
- R2 `yabomish-sync` manifest 擴充 — 該通道只搬靜態檔（`char_freq.json` 是語料不是學習資料）；學習資料走 FreqTracker 既有的 freq.json（syncFolder + iCloud）。

## 儲存

`freq.db` 新表（與 freq／bigram／pinned 同庫，WAL）：

```sql
CREATE TABLE IF NOT EXISTS lookup_history(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts REAL NOT NULL,
  mode TEXT NOT NULL,   -- "zh"（注音反查）| "to"（同音字）| "pys" | "pyt"
  query TEXT NOT NULL,  -- 注音字串（含調）｜同音基準字｜拼音+調數字
  char TEXT NOT NULL,   -- 選定的字
  code TEXT NOT NULL    -- 嘸蝦米碼，多碼以 / 相連
);
```

- 查字是低頻事件（一天個位數次）：**不做 pending batching**，直接在 bgQueue 上單發 insert（成本可忽略），寫入後修剪至上限 **1000 筆**（`DELETE ... WHERE id <= MAX(id)-1000`）。
- 讀取 `recentLookups(limit:)`：`bgQueue.sync` + `ORDER BY id DESC LIMIT ?`（與 pin() 同款同步模式）；不進熱路徑快取。
- `,,RS`（重置字頻）**不**清查字歷史；清除走獨立的 `,,RH`。

## 記錄點（InputEngine 共用引擎，macOS/iOS 同體）

選字送出共有 5 個現場，各補一行 `_recordLookup(...)`：

| 位置 | 模式 | query 來源 |
|---|---|---|
| `selectCandidate(at:)` 注音分支 | `zh` | `_lastZhuyinQuery`（`_zhuyinLookup` 存下的完整注音含調） |
| `selectCandidate(at:)` 同音分支 | `to` | `_sameSoundBase`（**取值要在 reset 之前**） |
| `_selectCandidateImpl(at:)` 注音分支（數字鍵路徑） | `zh` | 同上 |
| `_selectCandidateImpl(at:)` 同音分支 | `to` | 同上 |
| `selectPinyinCandidate(at:)` | `pys`／`pyt` | `_composing`（拼音+調，取值在 reset 之前） |

碼源：各分支本來就會 `cinTable.reverseLookup(char)` 顯示拆碼提示，直接重用該 `codes`。

不改現行頻率學習語意：注音模式下 `_composing` 為空、同音模式被 `!_isSameSoundMode` 擋掉，兩者本來就不記 freq，維持原狀。

## 指令

- `,,LH` — 檢視最近 20 筆（新→舊），格式 `N. 字 碼 ←查詢`，多行 commit（與 `,,H` 說明文字同一輸出通道）。空白時 toast「查字歷史：空白」。
- `,,RH` — 清除查字歷史（toast 確認）。
- 內建指令優先於 commands.json（既有契約）；`lh`／`rh` 不與 modeMap 衝突。MINIMAL 模式照常可用（查碼與字頻學習都是 MINIMAL 保留功能）。

## 同步（零新通道）

`FreqTracker.JSONStorage` 加入 `lookups: [LookupEntry]?`（optional → 舊 freq.json 回溯相容）：

- export：`SELECT * FROM lookup_history ORDER BY id` 全量帶出。
- import：以 `(ts,mode,query,char,code)` 五元組去重後 append，再修剪上限 — 單調合併，跨裝置不會互刪。
- 既有 macOS `syncViaSyncFolder`（freq.json）與 iOS `mergeFromiCloud`（freq.json）自動帶上，manifest 不動。

## 隱私

查字歷史 = 使用者主動查詢行為，只存本機 freq.db 與使用者自設的同步通道；不上網、無新型態遙測。同步安全條款（sync-v1.md「不含打字內容記錄」）語意不變：查字記錄是查碼事件，非鍵擊內容，且只走既有私有通道。

## 測試

- `FreqTracker(dir:)` 注入暫存目錄：記錄/順序/上限/清除/重開持久化。
- `,,LH`／`,,RH` dispatch：注入 tracker 驅動真引擎，驗 commit 文本與 toast。
- 引擎 5 個 hook 為單行呼叫，由 reviewer 走讀 + macOS `run_tests.sh` 全套回歸把關（Linux 環境無 swiftc，編譯驗證在 Mac）。

## iOS 落地

引擎與 FreqTracker 為共用原始碼；yabomish_ios 照既有流程同步這兩檔即可。儲存路徑沿用 `AppConstants.sharedDir`（與 freq.db 完全同一容器、同一權限行為）——若 iOS 鍵盤在無 Full Access 下對該路徑只讀，lookup_history 與字頻學習行為一致（既有 `mergeFromiCloud`／權限回補機制照常運作），不引入新的權限需求。
