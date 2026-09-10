# Changelog


## [0.3.64] — 2026-09-10

### 新功能

- **全新圖示（摺紙蝦）＋狀態列簡化** — App 圖示改為摺紙風格的捲曲蝦（macOS／iOS 同款，FLUX 生成）；狀態列／輸入法清單改顯示**文字**（移除 `tsInputMethodIconFileKey`），切換顯示收斂為 **Yabo（預設）／Yabomish** 二擇（移除繁中／🦐，舊值自動遷移）。menubar 用 icon.tiff 三方向檔同步換新蝦（方向偏好暫為同圖，預留）。注意：名稱變更需重新安裝或移除重加輸入法才會刷新 TIS 快取

- **聯想預先反白可開啟，預設關閉**（`docs/audits/20260909-suggest-preselect-option.md`）— 接續 0.3.63「Enter 不再代選第一個聯想詞」：剩下的「聯想列第 0 候選預先反白」做成開關，**預設關閉**——升級後純聯想顯示不再反白任何候選，數字鍵仍可直接選詞、方向鍵從第一個候選開始導航；偏好舊觀感者可在設定開啟。僅影響純聯想顯示（組字已空）；組字候選一律反白第一個。設定→輸入功能頁「聯想輸入」旁新卡片
- **Shift＋數字鍵輸出選項**（`docs/audits/20260908-shift-digit-option.md`）— 候選／聯想顯示中按住 Shift 再按數字列的輸出可選：「符號 !@#$%」（預設，全系統慣例）或「數字 12345」（原行為，聯想中快速插數字的出口）。設定→輸入功能頁兩卡單選。idle 狀態恆為符號；行為與 iOS 版對齊

### 修正

- **字級聯想條件字元取 `.first` → `.last`** — `BigramSuggest.suggest` 原以條件字串的首字元查表，多字送出（詞／snippet）時會接錯上文（例如送出「很好」後以「很」而非「好」預測下一字）；改取尾字，與 iOS 版對齊
- **網路版語料下載完成後即時生效** — `DataDownloader.ensureData` 原本只下載解壓，沒有任何重載路徑：`WikiCorpus`／`BigramSuggest` 為 singleton、僅在 init 讀檔，首次下載完成后聯想要等輸入法行程重啟才會活。現補上重載鏈（`WikiCorpus.reload()`＋`BigramSuggest.reload()`→`SuggestionEngine.reloadCorpus()`→`InputEngine.reloadSuggestionCorpus()`，於引擎鎖內執行避免與查詢競態），並在下載開始／完成時顯示提示（「下載聯想語料中…」／「聯想語料就緒」）、防重複下載（activateServer 每次切換視窗都會觸發）。失敗維持靜默記錄，下次啟用自動重試
- **純聯想顯示時空白鍵不收提示** — v0.3.63 起 Enter 會收掉聯想提示並把換行還給 app，但空白鍵輸出空白後提示窗仍滯留。現比照 Enter：輸出空白並收掉提示。注音／拼音反查等組字路徑不受影響
- **極簡版偏好設定無法編譯** — 未發行的 Shift＋數字鍵區塊引用 `#if !MINIMAL` 下的 `shiftDigitOutput`，`-DMINIMAL` 建置直接編譯失敗；區塊與卡片 helper 補上編譯旗標
- **組字中 Shift+8 萬用碼被攔截** — shift 區塊內數字分支排在萬用碼分支之前，組字中（候選非空）按 Shift+8 會變成「送出第一候選＋插入字面 8」，萬用碼幾乎不可達；現萬用碼分支移至最前，一律生效
- **行為自相矛盾消除** — 原「有候選時 Shift+數字→數字、idle 時→符號」改為「有候選→依偏好、idle→恆符號」

### 改進

- **手冊與 README 全面修訂**（`docs/audits/20260910-manual-review.md`）— 雙子代理逐章對照程式碼審計後修訂：iOS 章移除已刪的跨裝置同步／Hermes 並補新功能現況；安裝章／README 改為 DMG 兩包制為主；修正 yabomish.sh 選項號（更新 4→1、移除 6→5）與「移除不刪使用者資料」錯述；`~/Library/YabomishIM/` 舊路徑全改為 `Application Support/Yabomish/`；刪 `user_phrases.txt` 與「注音反查」開關（均已不存在）；`Shift+Tab` 上一頁、日文 toast「仮」、虛詞清單、自動送字條件等描述對齊程式碼；命令表補 `,,LH/,,RH/,,SG/,,V 系列/,,X 系列`；偏好章補查字歷史 GUI、Emoji 第四卡、外觀三態；「36 部專業詞典」口徑統一為 28（36 為 terms bin 檔數，含 8 個一般詞庫）
- **發佈改為兩包制：「精簡」與「全量」，各為可雙擊安裝的 DMG（2.8MB），訊息繁／簡／英三語** —
  `tools/release.sh`（`lite` 預設／`full`）產出 **Yabomish-精簡.dmg** 與 **Yabomish-全量.dmg**：包名即選項，雙擊「安裝 Yabomish.app」→ 管理員授權 → 自動安裝輸入法到 `/Library/Input Methods`、偏好設定到 `/Applications` → 佈署使用者層資源並寫入語料等級偏好（`corpusVariant=lite/full`）→ 重啟輸入法 → **自動開啟系統設定的輸入方式列表**（`?InputSources` 深連結，實測可跳過上層頁面直接按 +）。安裝訊息依系統語言顯示繁中／簡中／英文。
  差異只在首次打字的自動下載（SHA-256 驗證，存於 `~/Library/Application Support/Yabomish/`，`WikiCorpus.resolvePath` 優先讀取故下載後即生效）：**精簡**＝基礎語料（約 15MB）；**全量**＝全量語料＋28 部專業詞典＋一般詞庫（約 100MB）。離線時打字、查碼、繁簡轉換不受影響。
  語料 zip 已備於 `build/`（`yabomish-corpus-{lite,full}-0.3.64.zip`，雜湊見 `build/corpus-hashes.txt`），Release 上傳後以 `tools/make_corpus_manifest.py --tag vX --sha256 <lite> --full-sha256 <full>` 重產清單；manifest 未含 full 段時「全量」自動降級下載基礎語料。極簡版退出預設發佈（`yabomish.sh` 仍可安裝）。
  **Yabomish-精簡.pkg／全量.pkg 為選配**：需 Developer ID Installer 憑證（存在時自動偵測並簽署，`WITH_PKG=1` 強制產出未簽署測試版）；notarytool 公證流程涵蓋 DMG 與 pkg
- **Emoji 聯想可調整與關閉** — 設定程式「聯想與詞庫」頁的聯想層順序新增第四張「Emoji 聯想」卡片（原為硬編碼固定排最前且無法關閉）：拖到最前維持既有行為、移到其他位置則文字聯想優先（聯想列 10 格有空位才顯示 Emoji）、點擊卡片完全關閉。此偏好為全域設定，不隨語境設定檔切換；MINIMAL 版與極簡安裝（無 emoji 字元對照表）不受影響


## [0.3.63] — 2026-09-07

### 修正

- **Enter 不再代選第一個聯想詞** — 純聯想顯示（組字已空）時按 Enter，原行為會送出高亮的候選詞；現收掉提示並把換行原樣還給 app（選詞請用數字鍵，Escape 收提示）。VRSF 快選等需要組字的路徑不受影響
- **設定程式「聯想與詞庫」頁版面重疊** — 聯想層順序／詞庫網格以 GeometryReader 包裹，在 ScrollView 內框架塌陷導致區塊互疊（拖放功能引入的舊疾）；量測改掛 background，拖放排序行為不變

### 新功能

- **剪貼簿還原** — `,,V` 系列貼上後 0.55 秒自動還原使用者原剪貼簿（期間有複製動作則不覆寫），不再永久破壞剪貼內容
- **蝦頭方向即時換圖** — 偏好設定的蝦頭方向原為安裝時一次性設定；現選擇時經管理者授權即時更換輸入法圖示並重啟輸入法，取消授權自動回復

### 改進

- **語料下載 manifest 化** — 下載網址與 SHA-256 移出 Swift 硬編碼，改由 `corpus_manifest.json` 驅動；新增 `tools/make_corpus_manifest.py`，日後更新語料不必改程式碼
- **DebugLog 惰性求值** — 除錯關閉時熱路徑日誌字串零成本；寫入加鎖
- **退回顯示模式可點選** — 不相容 app 的 fallbackFixed 模式接上候選字點擊命中
- **文件整併** — 設計文件與盤點報告分別歸入 `docs/design`／`docs/audits`
- **誌謝與資料來源加註** — README 補齊全部詞庫來源與授權（拼音對照、萌典詞組、NER、日本熟語、晶晶體、中式流行語），新增誌謝段落與嘸蝦米字表自備聲明


## [0.3.62] — 2026-09-07

### 新功能

- **介面外觀三態切換** — YabomishPrefs「外觀」頁新增自動（跟隨系統）／淺色／深色選項：候選字窗（游標＋固定模式）、切入提示與字根提示即時套用所選外觀，不必重登輸入法；偏好設定視窗本身同步切換方便預覽。預設「自動」，既有使用者行為不變；舊版偏好遷移已涵蓋 `appearanceMode` key
- **`,,RL 重載字表** — 說明文字自始宣稱的指令本輪才真正實作（原本回「未知命令」），與偏好設定存檔／匯入後的 `reloadTables` 通知執行同一組重載（字表＋自訂指令＋snippets）

### 修正

- **固定模式滑鼠點擊命中測試** — 原本點擊任何候選位置都送出第 1 個字；現以逐段寬度量測建立命中矩形，未命中不送字，文字被截斷（85% 螢幕寬上限）時停用點擊選字
- **字頻資料落盤與同步** — 每個輸入 session 原本各建獨立 FreqTracker，flush 對象錯置：未滿批次的字頻可能永不寫入、freq.json 跨裝置同步在 macOS 永不執行；改為共用實例＋啟動時背景 deferredMerge
- **匯入新字表立即生效** — 匯入後清除的快取檔寫錯對象（`liu.cin.cache` 不存在），且 `liu.bin` 無新鮮度檢查，二次匯入永遠載舊表還回報成功；現以 mtime 檢查自動重編，匯入改走正規路徑（`~/Library/Application Support/Yabomish/`）＋`%chardef` 內容驗證＋原子替換
- **CINTable 併發安全** — 主執行緒查表與背景預熱／重載共用狀態無鎖（可能 crash）；全面加鎖，編譯移至鎖外避免重載期間打字凍結
- **emoji 候選字刪除錯位** — IMK 範圍改以 UTF-16 長度計算，非 BMP 字元不再刪除半個 surrogate pair
- **偏好變更不再卡打字** — prefsChanged 廣播去抖 0.5 秒＋重載改背景執行；啟動不再同步全量載入語料；注音表加入背景預熱並上鎖
- **YabomishPrefs** — 查字歷史顯示「,，」全形逗號錯字（照打無效）；快捷碼 CSV 匯出補欄位跳脫（含逗號／引號／換行）與 BOM；說明文件 `';`／`,,ZH` 不一致（查證 `,,ZH` 為唯一入口）全部對齊；`UserDefaults` suite 強制解包移除
- **建置版本號** — CHANGELOG 頂端為 `[Unreleased]` 時產出字面 "Unreleased" 版本字串；改取最新語意化版本

### 重構

- **repo 瘦身：大型資料檔遷移 Git LFS** — 歷史中的 `.bin`（911MB）／`.csv`／`.ods`／`.tsv`／`.parquet` 共約 1.1GB 以 `lfs migrate import --everything` 全歷史改寫（343 commits），新 clone 僅取現役資料。⚠️ 歷史 hash 全變，其他機器需重新 clone；遷移前備份 bundle 保留於 `/tmp/yabomish-pre-lfs-backup.bundle`
- **偏好快照** — 熱路徑每擊鍵 6–10 次 UserDefaults 讀取改為內部快照（NSLock 保護、setter 即時刷新、跨程 prefsChanged 通知同步），打字手感更穩
- **YabomishPrefs 卡片元件統一** — 7–8 份近乎相同的選擇卡片抽成共用 `SelectableCardView`（視覺逐欄位等價），順帶補齊聯想頁卡片的無障礙標籤；CSV 跳脫抽成共用 `csvEscape()`；查字歷史 DateFormatter 改 static 快取
- **輸入法去重** — toast 建視窗×2、候選導航×3、「送首選或跳離」×4、候選索引反查×7、拼音聲調×2 各合併為單一實作（行為逐項保持；行為已分歧的死版 `selectCandidate` 隨死碼刪除）
- **死碼清理（−500+ 行）** — 刪除 `PhraseLookup`（省 SQLite 常駐快取）、`UserPhrases`、`DomainMerger` 整檔與 `htmlToMarkdown` 等零引用程式碼；引擎死 API（`undoLastLetter`／`selectByDigit` 等）；「注音反查」「新引擎」等無效開關與對應死偏好屬性；README／測試腳本過期條目

### 行為變更

- **切換視窗時丟棄組字** — `deactivateServer` 不再代送第一候選字：使用者切換視窗／app 時，未經確認的組字一律丟棄（macOS 內建注音等多數 IM 慣例），不再憑空落入底文
- **實驗分支 `experiment/async-suggest`** — 聯想查詢移出主執行緒（可注入 executor＋世代防護），附帶為 WikiCorpus 補上完全缺失的併發鎖（lazy init 背景載入與主執行緒 reloadDomains 的既有競態）；**未定案合併**，待真實打字評估

### 移除

- **打字練習 YabomishPractice** — 已拆分至獨立倉庫 `yabomish_cahiers`（打字練習程式自成一體）；`yabomish.sh` 選單 6 同步移除。執行期資料（liu.bin／char_freq.json／freq.db、profiles 結構、UserDefaults key）完全相容，舊練習記錄在新倉庫版直接沿用

## [0.3.61] — 2026-08-25

### 新功能
- **查字歷史** — 注音反查（`,,ZH`）、同音字（`,,TO`）、拼音查碼（`,,PYS`／`,,PYT`）選字送出時自動記錄至 freq.db（`lookup_history` 表，上限 1000 筆）——這份清單就是「不會拆碼的字」。`,,LH` 檢視最近 20 筆（`字 碼 ←查詢`），`,,RH` 清除；`,,RS` 重置字頻不影響查字歷史。記錄隨 freq.json 一起走既有同步通道（macOS syncFolder／iOS iCloud，五元組去重單調合併）。MINIMAL 模式照常可用。設計細節見 `doc/20260825-lookup-history.md`
- **查字歷史 GUI** — YabomishPrefs「輸入」頁新增查字歷史區塊：檢視全部反查選字記錄（新→舊，含模式與時間）、匯出 CSV（UTF-8 BOM，Excel 直接開啟不亂碼）、一鍵清除。直接唯讀 freq.db，與輸入法即時一致
- **打字練習 YabomishPractice.app** — 獨立看打練習程式（`yabomish.sh` 選單 6）：常用字／一二碼字／弱點字／隨機字四種題源、10/20/50 字一輪或自訂文章；**空白鍵即打即送**（Enter 亦可）、免點擊自動聚焦；結算顯示每分鐘字數與準確率、成績歷程記錄。題目由使用者自備拆碼表＋公共語料字頻即時生成，弱點字直接取自查字歷史與練習錯字；不連網、不隨附任何表格資料

格式基於 [Keep a Changelog](https://keepachangelog.com/)。

## [0.3.60] — 2026-08-18

### 修正
- **徹底移除單碼空白防搶送 guard** — 先前版本在可延伸單碼按空白時跳出「再按空白確認」提示，造成輸出中斷；guard v2 信任名單僅存記憶體、程序重啟即歸零，等於每個 session 重複干擾。現已完全移除：空白一律直接送出第一候選，測試同步改為直接送出合約（87/87 passed）

### 新功能
- **「切換顯示」選項** — 偏好設定新增狀態列／輸入法名稱顯示切換（繁中 / Yabomish / 🦐），安裝時寫入 Info.plist 的 CFBundleName

## [0.3.59] — 2026-08-16

### 新功能
- **極簡安裝模式** — `./yabomish.sh` 新增第三種安裝模式：以 `-DMINIMAL` 編譯旗標將聯想與詞庫整組移除，輸入法縮至約 2MB；保留打字、注音／拼音／同音字查碼、繁簡轉換、字頻學習與 `,,PIN` 固定排序、擴充表、快捷碼（#13，@plateaukao）
- **游標跟隨橫向模式** — 游標跟隨選字窗可切換為水平排列（設定程式 → 外觀），方向鍵自動適配：←→ 移動候選、↑↓ 翻頁（#7）

### 修正
- **選字窗寬度自動縮放** — 游標模式下隱藏中的固定模式標籤殘留 Auto Layout constraint，把視窗寬度撐在舊尺寸；改為切換佈局時停用／啟用該組 constraint，寬度隨候選字數縮放（#12，@plateaukao）
- **停止追蹤二進位字典檔** — 44 個 `YabomishIM/Resources/*.bin` 與 `wiki_ner_entities.parquet`（約 170MB）自 git 索引移除，repo 不再隨字典重建膨脹。注意：既有 clone 在 pull 後工作目錄的字典檔會被移除，請先備份或重新產生（#11，@plateaukao）

### 改進
- `LSMinimumSystemVersion` 明定 14.0
- 新增 `tools/release.sh`：Developer ID 簽章 + dmg 打包（notarization 需另行提供憑證）
- 修復 `run_tests.sh` 先前無法編譯的問題（測試 stub 重複定義、缺 `engineDidShowCodeHint`），全套 80 tests passed

## [0.3.58] — 2026-07-30

### 新功能
- **同音字模式自動退出** — 新增 `homophoneAutoExit` 偏好設定（預設關閉）。開啟後，同音字查詢選字送出即自動退出同音字模式，符合傳統嘸蝦米「同音字」使用習慣
- **版本號顯示** — Yabomish 設定程式的「關於」頁與標準 About panel 皆顯示版本號，回報問題時可直接取用

### 改進
- **版本來源統一** — `build_im` 與 `build_prefs` 皆以 `CHANGELOG.md` 首行版本為單一來源，同時寫入 `CFBundleShortVersionString` 與 `CFBundleVersion`

### 文件
- **同步使用手冊與使用說明** — 補充 `同音字自動退出`、`Debug 模式` 說明，修正資料路徑為 `~/Library/Application Support/Yabomish/`，並說明舊版 `~/Library/YabomishIM/` 仍作為 `liu.cin` 匯入路徑的向後相容 fallback

### 修正
- **游標選字窗寬度不會隨候選字縮小** — 隱藏中的固定模式標籤殘留 Auto Layout constraint 與舊文字，把視窗寬度撐在舊尺寸；改為切換佈局時停用／啟用該組 constraint，選字窗寬度隨候選字數自動縮放

---

## [0.3.57] — 2026-04-27

### 新功能
- **剪貼簿處理指令** — `,,V` 貼上純文字（去格式）、`,,VT` 貼上簡→繁、`,,VS` 貼上繁→簡。透過模擬 Cmd+V 實現，換行正確保留
- **自訂指令系統** — `commands.json` 外部設定檔，支援 `open`（開啟 app）和 `shell`（執行腳本）兩種類型。`,,RL` 重載時一併載入
- **截圖指令** — `,,SS`（全螢幕）、`,,WS`（當前視窗）、`,,CS`（游標框選），存桌面 + 進剪貼簿。失敗時自動引導開啟螢幕錄製權限

### 修正
- **CIN 匯入灰掉無法選取** — `.cin` 非系統認識的 UTType，`NSOpenPanel` 改為 `[.plainText, .data]`，修復啟動引導和設定程式共 4 處
- **CIN 字表路徑 fallback** — `cinPath` 加入舊路徑 `~/Library/YabomishIM/liu.cin` 的 fallback
- **NSOpenPanel 焦點問題** — 所有 `NSOpenPanel` / `NSSavePanel` 加入 `NSApp.activate`
- **同音字模式下 ,, 命令被攔截** — 逗號不再被同音字模式吃掉，`,,to` / `,,t` / `,,h` 等可正常使用
- **Esc 一鍵解除特殊模式** — 同音字、注音、拼音模式下按 Esc 即可退出，不需再打 `,,TO`
- **聯想/emoji 候選操作** — composing 為空時左右鍵可選擇候選字、Enter 可確認送出
- **首次啟動延遲** — CIN 匯入後提前編譯 code table
- **安裝流程** — 嘗試直接啟動輸入法，減少需要 logout
- **引導畫面** — 新增「登出再登入」提醒頁

### 移除
- **`,,VM` 貼上轉 Markdown** — 無實際落地場景

---

## [0.3.56] — 2026-04-25

（已合併至 0.3.57）

---
- **截圖指令範例** — `,,SS`（全螢幕）、`,,WS`（當前視窗）、`,,CS`（游標框選），存桌面 + 進剪貼簿

### 修正
- **CIN 匯入灰掉無法選取** — `.cin` 非系統認識的 UTType，`NSOpenPanel` 的 `allowedContentTypes` 改為 `[.plainText, .data]`，修復啟動引導和設定程式共 4 處
- **CIN 字表路徑 fallback** — `cinPath` 加入舊路徑 `~/Library/YabomishIM/liu.cin` 的 fallback，避免升級後找不到字表
- **NSOpenPanel 焦點問題** — 所有 `NSOpenPanel` / `NSSavePanel` 加入 `NSApp.activate(ignoringOtherApps: true)`

### 移除
- **`,,VM` 貼上轉 Markdown** — 能吃 Markdown 的 app 自己處理 HTML 貼上，不能吃的貼 Markdown 語法更亂，無實際落地場景

---

## [0.3.55] — 2026-04-20

### 新功能
- **語境預設重新設計** — 4 組預設語境：⌨️ 預設（df）、🇹🇼 台式（tw）、🇨🇳 中式（ch）、💻 科技（tc），各自搭配對應詞庫組合
- **語境重置** — `,,XRS` 或 `,,XDF` 回到預設語境（無專業詞庫）
- **語境編輯器** — 設定程式中右鍵 profile 可「編輯」（彈出 sheet 修改所有欄位）或「複製」為新 profile
- **設定程式 Cmd+Q** — 加入 App menu，支援 Cmd+Q 關閉

### 改進
- **用詞習慣移至聯想分頁** — 臺灣用詞/中式用詞從「輸入」移到「聯想與詞庫」，與語境切換放一起
- **語境切換說明** — 設定程式中加入操作提示（點擊切換、右鍵編輯、命令碼說明）
- **詞庫查詢分列顯示** — 匹配詞條改為每詞一行，不再用頓號擠在一起
- **查碼提示延長** — 注音/同音字查碼模式下拆碼提示顯示 3 秒（一般模式 1.5 秒），不再一閃而過

### 修正
- **同音字模式逗號命令** — 修正同音字模式下 `,,` 命令被擋住的問題，`,,T` 等命令可正常切回（#6 延伸）
- **語境切換整組替換** — 修正切換語境時舊詞庫未關閉的問題，現在先關全部再開 profile 指定的

---

## [0.3.54] — 2026-04-19

### 新功能
- **語境切換器** — `,,X` + 自訂碼一鍵切換輸入模式、聯想策略、詞庫組合、地區用詞。`,,XS` 儲存、`,,XI` 顯示當前語境。最多 10 組，設定程式可管理、匯入匯出
- **聯想快速開關** — `,,SG` 切換聯想系統開關

### 修正
- **Shift 清除字根** — composing 中按 Shift 會先清除已輸入字根再切英數模式（#6）
- **空白鍵清除無效碼** — 不滿四碼且查無候選時，按空白鍵清除字根而非卡住（#6）
- **快捷碼新增驗證** — 修正超過 4 碼仍顯示「可用」的問題，新增碼長上限檢查（2–4 碼）
- **快捷碼字表衝突偵測** — 修正 CIN 碼表無法載入導致所有碼都顯示「可用」的問題（magic bytes CINB→CINM、header offset 修正、新增 Application Support 路徑）
- **快捷碼匯入驗證** — 匯入時檢查碼長度（2–4 碼）與字表衝突，略過不合法的碼並顯示匯入結果摘要

---

## [0.3.52] — 2026-04-17

### 修正
- **同音字查碼讀音誤判** — 「同」查出「痛」等破音字讀音錯誤問題。改回以萌典字表為基礎（9913 字），用 wiki 語料庫頻率修正 333 個破音字的讀音排序（常用讀音排前），補入威注音獨有 372 字，合計 10285 字
- **ZhuyinLookup 排序邏輯** — 同音字查碼不再按「同音字群字頻總和」選讀音，改用 `char_to_zhuyins` 原始順序（第一個 = 最常用讀音）

### 工具
- 新增 `tools/fix_zhuyin_reading_order.py` — 合併萌典＋威注音字表、修正破音字讀音順序的工具腳本

---

## [0.3.51] — 2026-04-16

### 新功能
- **固定同碼字排序** — 新增 `,,PIN` / `,,UNPINx` 命令，指定同碼字的候選順序（如固定「手」排在「乎」前面），不受字頻 decay 影響。FreqTracker 新增 `pinned` 表，InputEngine 新增 pin mode 狀態機
- **高對比模式** — 新增 `highContrast` 偏好設定，候選字加粗＋文字陰影，方便視覺辨識
- **首次使用提示** — 匯入字表後顯示「空白鍵送字 ｜ Shift 切英文 ｜ ,,H 說明」引導訊息
- **候選字面板引導** — 新增 `showGuide()` 方法，尚未匯入字表時顯示引導訊息
- **設定程式 Edit menu** — 加入 Undo/Redo/Cut/Copy/Paste/Select All，Cmd+C/V/X/A 在文字欄位中正常運作

### 改進
- **設定程式 UI 大改版**
  - 外觀分頁：GroupBox 改為卡片式 UI（字型滑桿＋即時預覽＋功能卡片＋蝦頭方向卡片）
  - 輸入分頁：新增選字窗 demo 預覽、固定同碼字排序區塊（PinnedOrderSection）
  - 快捷碼分頁：移除 GroupBox 改用 SectionDivider＋Label 分區、新增快捷碼編輯按鈕（✎）、支援 `#` 註解行、路徑遷移至 `~/Library/Application Support/Yabomish/tables/`
  - 聯想與詞庫分頁：加入 SectionDivider 分區
- **擴充表載入改善** — CINTable 載入擴充表時跳過空行和 `#` 註解行
- **未知命令提示** — 顯示「未知命令」時建議輸入 `,,H` 查看說明
- **安裝腳本簡化** — `yabomish.sh` 不再詢問蝦頭方向和狀態列名稱（改從設定程式調整），精簡安裝說明

### 移除
- **PrefsWindow** — 刪除輸入法內建的偏好設定視窗，改為引導使用者開啟 YabomishPrefs.app
- **DomainCardView / DomainCollectionController** — 舊的 AppKit 詞庫卡片 UI 刪除，DomainOrderManager 獨立為新檔案

---

## [0.3.50] — 2026-04-15

### 新功能
- **詞庫查詢** — 快捷碼頁頂部新增查詢功能，輸入中文詞即可查看收錄於哪些詞庫，並列出實際匹配詞條，支援匯出 CSV

### 修正
- **NAER 垃圾詞條清除** — 移除「是否是退伍軍人」「想法一致太好了」等 16 筆非術語詞條
- **NAER 拆分改善** — 正確處理 (1)(2) 編號格式、半形括號、引號，長度上限 8→16 字
- **cn_slang 短詞遺失** — 修復 build_prefix min_len=4 導致 59% 短詞（牛逼、內卷、擺爛等 1840 筆）被丟棄的問題
- **WBMM bin 格式一致化** — 全部統一為 suffix 格式（prefix + value = 完整詞），消除查詢時重複拼接問題
- **路徑統一** — 所有程式碼統一使用 `~/Library/Application Support/Yabomish/`，消除三個路徑並存的問題（DebugLog、PrefsWindow、CINTable、DataDownloader、PhraseLookup）
- **`'` `;` `/` 完整直送** — composing 中按這三個鍵會先送字再直送，英文模式下也能正確輸出 `'`
- **安全輸入偵測** — 切換到密碼欄位時清除 composing 並隱藏候選字面板
- **模式互斥** — `,,ZH`、`,,TO`、`,,PYS`/`,,PYT` 進入時互相清除對方的旗標，不再可能同時啟用多個模式
- **同音字模式穩定性** — 打碼查不到字或 backspace 刪到空時不再意外退出同音字模式（只有 Escape 才退出）
- **Shift 快按保護** — composing 中快按 Shift 不再觸發中英切換
- **deactivate 清模式** — 切換 app 時正確退出注音/拼音模式
- **線程安全** — 公開存取器改用 NSRecursiveLock，delegate 回調中讀取屬性不再 data race

### 改進
- **關於頁面** — 加入 GitHub 原始碼連結，更新路徑說明和快捷鍵速查
- **`.gitignore`** — 排除 `YabomishIM/Resources/*.bin`（94MB 語料不再追蹤）

---

## [0.3.49] — 2026-04-14

### 變更
- **`'` `;` 空閒直送** — 不再攔截單引號和分號，直接傳給 App。寫程式時 SQL 字串、JavaScript 引號、shell script 等場景不再被輸入法干擾
- **頓號回歸 `vv`** — 移除 `,,D` 命令，頓號「、」直接用嘸蝦米碼 `vv` + 空白鍵（5.7 版起的標準做法）
- **注音查碼只留 `,,ZH`** — 移除 `';` 快捷鍵切換注音模式
- **同音字模式簡化** — `,,TO` 進入後直接打碼，不再需要 `'` 前綴

### 修正
- **移除腳本路徑修正** — `yabomish.sh` 的 `USER_DIR` 改為 `~/Library/Application Support/Yabomish`（與 Swift 程式一致），移除時不再殘留字表和字頻資料
- **安裝覆蓋問題** — 安裝前先刪除舊 app，避免完整版→精簡版切換時殘留 `terms_*.bin`
- **字表偵測** — 安裝後同時檢查 `liu.cin` 和 `liu.bin`

---

## [0.3.48] — 2026-04-14

### 新增
- **精簡安裝模式** — `yabomish.sh` 選項 2，不含聯想語料（~3MB），適合只需要基本嘸蝦米輸入的使用者

### 移除
- `trigram_suggest.json`（5.4MB）、`bigram_suggest.json`（0.3MB）— 死檔，程式碼未引用
- `yabomish_data/korean/kengdic.tsv`（11MB）、`yabomish_data/kautian/kautian.ods`（4MB）— 重複的原始語料

---

## [0.3.47] — 2026-04-14

### 新增
- **NAER 語料補齊** — 從 parquet 直接建 bin，覆蓋率 84% → 99.5%（+293K 詞條，217 個子分類全部對應）
- **NAER domain 拆分** — 專業詞典 23 → 28 個：`eng` 拆為土木水利/航太/核能/紡織食品，`bio` 拆為動物生態/植物/魚類
- **專業詞典 badge** — 設定程式「聯想與詞庫」頁，專業詞典收合時顯示已啟用數量（如 3/28）
- **擴充表修正碼優先** — 擴充表（`tables/*.txt`）的字排在主表前面，可用於修正碼表錯誤

### 改進
- **NAER 詞條清洗** — 分號/逗號拆分多義詞、去括號注釋（全形/半形/方括號/黑括號）、去英文、詞長限 3-8 字
- **中國流行語清洗** — 移除 72 筆模板句（xx/XX）、解釋性文字、格式錯誤（3,119 → 3,047）
- **bin 總大小** — 185MB → 74MB（清洗 + 拆分後）

### 修正
- **clone URL** — README、usage.md、安裝手冊改為正確的 GitHub URL
- **.gitignore** — 修正 gen_pinyin_data.py/vChewing-macOS 黏在一行的 bug
- **git 歷史清理** — filter-repo 移除已刪除大檔，.git 6.5GB → 226MB

### 變更
- 移除 git tracking：YabomishPrefs.app 建置產物、data/ 殘留檔案、大 parquet、學術論文 PDF
- 專業詞典數量：×20 → ×28（README、HelpTab、手冊同步更新）

---

## [0.3.44] — 2026-04-14

### 新增
- **快捷碼管理** — 設定程式新增「快捷碼」分頁，空碼綁定自訂文字／指令（agent prompt、簽名檔等），支援匯入匯出
- **匯入字表** — 設定程式「輸入」頁頂部新增匯入按鈕，附使用說明
- **專業詞典分類** — 5 大類標題（商業醫學/人文社科/資訊工程/自然科學/地理軍事）
- **語料來源與授權** — 「關於」頁底部列出所有資料來源與授權

### 改進
- **設定程式 UI 統一化** — 新增 Typo.swift design tokens（14 字體 + 9 色彩），全域一致
- **字體大小提升** — 最小字從 10pt → 11pt，正文統一 13pt
- **視窗加寬** — 580×480 → 640×520，5 個 tab 不再擠
- **分頁合併** — 「使用方法」+「說明」+「語料授權」合為「關於」頁

### 移除
- **近似義功能** — 移除 terms_semantic.bin（29MB）、雙排候選窗、Shift+數字替換、build_semantic.py
- **emoji.txt 部署** — 改用 emoji_char_map.json 聯想，maxCodeLength 回到 4（恢復滿碼自動送字）

### 修正
- **Chrome 網址列游標跟隨** — 改用 `attributes(forCharacterIndex:lineHeightRectangle:)` 取代 `firstRect`（參考 OpenVanilla，感謝 @tzyyung 回報）
- **安裝腳本亂碼** — 蝦頭方向/狀態列名稱提示改為純文字，修正終端機顯示問題

### 變更
- 設定程式更名：「Yabomish 偏好設定」→「Yabomish 設定」
- `'` 鍵回歸官方行為：空閒時輸出頓號「、」（同音字改用 `,,TO` 命令）
- 新聞詞頻來源更正為「國家教育研究院 新聞語料庫」

---

## [0.3.43] — 2026-04-13

### 新增
- **語料大擴充** — 一般詞庫從 6 個增至 13 個
  - 歇後語 14,032 筆（chinese-xinhua, MIT）
  - 台灣俗諺 428 筆（教育部閩南語辭典）
  - 客語辭典 19,570 筆（教育部六腔：四縣/海陸/大埔/饒平/詔安/南四縣）
  - 韓語漢字詞 33,414 筆（Kengdic, MPL 2.0）
  - 台灣地名 519 筆（教育部本土語言地名, CC-BY 3.0 TW）
  - 台語學科 4,553 筆（教育部台語學科, CC-BY 3.0 TW）
  - 晶晶體 188 筆（自建，獨立 poolJJ，單字觸發）
- **兩岸用詞切換** — 偏好設定新增紫色卡片，82K 詞兩岸標記，runtime 降權
- **管理程式（YabomishPrefs.app）** — 獨立 SwiftUI 偏好設定 App
  - 五分頁：輸入、聯想與詞庫、外觀、使用方法、說明
  - 首次使用三頁引導（匯入字表 → 加入輸入方式 → 常用快捷鍵）
  - 詞庫卡片拖拉排序、啟用／停用
  - 專業詞典顯示詞數
- **三層聯想輸入** — 詞級語料（萌典/維基/新聞）→ 詞庫 → 字級（bigram/trigram）
- **yabomish_data/** — 明碼語料目錄，16 子目錄各附 SOURCE.md（來源、授權、格式、build 指令）
- **學術論文收錄** — doct/papers/（Stupid Backoff、Smoothing、MoE 等）

### 改進
- **FreqTracker: stupid backoff + 歸一化** — 取代 raw count 加權，bigram 命中用機率，未命中 fallback unigram × 0.4
- **FreqTracker: 批次緩衝寫入** — 每 50 筆 flush 一次 SQLite（BEGIN/COMMIT），I/O 減少約 50 倍
- **FreqTracker: 自適應 stupid backoff** — alpha 值從硬編碼 0.4 改為根據 session 內 bigram 命中率自動調整（前 100 次查詢用 0.4 暖機，之後用實際 miss rate）
- **word_ngram.bin 清洗** — 移除 46% 垃圾 key（英文/數字/wiki markup），7.4MB → 2.8MB
- **terms_*.bin 重建** — 純 NAER + 維基 freq≥10 過濾，砍掉 90-99% 冷門實體
- **所有 domain bin 最短 prefix 改為 2 字** — 排除單字觸發噪音（晶晶體保留單字觸發）
- **CIN 檔案大小限制** — 100MB + 500K 行，防止惡意/損壞檔案耗盡記憶體
- **關鍵路徑錯誤處理** — WikiCorpus/BigramSuggest/DomainMerger/ZhuyinLookup 的 try? 改 do/catch + DebugLog

### UI
- **對比度修正** — 亮色/暗色模式候選字窗可讀性改善
- **專業詞典兩欄 chip 佈局** — 節省空間
- **地區用詞切換** — 紫色卡片，「臺灣正體」/「简体中文」
- **說明 tab** — 快捷鍵速查表
- **新引擎 toggle 藏入 debug mode**
- **預設排序重排** — 一般詞庫/專業詞典按使用頻率重排

### 變更
- 字頻儲存從 JSON 遷移至 SQLite WAL
- 偏好設定 UI 從 AppKit 重構為 SwiftUI 獨立 App
- deactivateServer 時自動 flushAll() 確保字頻不遺失

---

## [0.2.17] — 2026-03-31

### 修正
- 全螢幕 App（cmux / Ghostty 等）中候選字窗不顯示：`collectionBehavior` 加入 `.fullScreenAuxiliary`

---

## [0.2.16] — 2026-03-31

### 修正
- 多螢幕環境下固定候選字窗跑到錯誤螢幕
- `activeScreen` 改為優先用滑鼠位置判斷所在螢幕
- CGWindowList fallback 改為找 frontmost app 面積最大的視窗

---

## [0.2.15] — 2026-03-26

### 修正
- 同音字查詢混入不相關字（查「社」出現「色」「庫」）
- 根本原因：萌典收錄所有讀音不分常用罕用
- 改用[威注音 VanguardLexicon](https://atomgit.com/vChewing/vChewing-VanguardLexicon)字表重建 `zhuyin_data.json`
- 多音字預設只顯示最常用讀音（可透過 `homophoneMultiReading` 開啟）

---

## [0.2.14] — 2026-03-24

### 修正
- 同音字 step 2 打碼後空白鍵送字失效

---

## [0.2.13] — 2026-03-24

### 新增
- 拼音查碼模式：`,,PYS`（簡體字＋簡體碼）/ `,,PYT`（繁體字＋繁體碼）
- 輸入拼音字母 + 聲調數字 1-5（空白鍵 = 一聲）查碼
- 支援 `v` → `ü` 轉換

### 修正
- 游標跟隨模式：選字窗左邊界溢出修正

---

## [0.2.12] — 2026-03-23

### 修正
- 游標跟隨模式：改善 `hasCursor` 判斷，加入視窗高度檢查與螢幕範圍驗證
- `install.sh`：修正 `defaults read` 回傳值含尾隨空白

---

## [0.2.11] — 2026-03-17

### 修正
- 滿碼自動送字：關閉偏好設定時仍會在碼長溢出時自動送字
- 擴充表解析：支援空格分隔（原本只支援 tab 分隔）

### 變更
- 程式碼重新命名：`sameSound` → `homophone`

---

## [0.2.10] — 2026-03-17

### 新增
- 擴充表系統：`~/Library/YabomishIM/tables/*.txt` 放入 tab-separated 檔案即可擴充字表
- 支援 iCloud 同步（共用字頻同步路徑下的 `tables/` 目錄）
- 安裝時自動部署 `emoji.txt`（1,906 個 Unicode 16.0 emoji，`em` 開頭五碼）
- `,,RL` 命令：重載字表 + 擴充表
- 偏好設定「匯入字表」：自動判斷 `.cin`（主表）/ `.txt`（擴充表）
- 偏好設定「編輯擴充表」：直接開啟 tables/ 目錄
- 候選字窗滑鼠點擊直接送字
- 空白鍵送出方向鍵選取的候選字

### 變更
- 碼長上限改為動態計算（從載入的字表自動推導）

---

## [0.2.8] — 2026-03-17

### 修正
- 注音鍵位對應修正：ㄛ/ㄨ/ㄟ/ㄩ/ㄝ 五個韻母 keyCode 對應錯誤

---

## [0.2.7] — 2026-03-16

### 新增
- `,,ZH` 命令：切換注音查碼模式（同 `';`）
- `,,TO` 命令：進入同音字查詢模式

### 修正
- 先按 `'` 再打碼的同音字流程無法正確查表

---

## [0.2.6] — 2026-03-15

### 新增
- 全型空格：`,,` + Space 或 Shift+Space 送出全型空格（U+3000）
- 字頻同步：偏好設定可指定同步資料夾（如 iCloud Drive），跨機共享字頻學習資料

### 修正
- 偏好設定視窗前景化

### 變更
- 偏好設定 UI 分組：選字窗、輸入、外觀、資料、除錯

---

## [0.2.4] — 2026-03-15

### 新增
- 注音模式選字後直接送出字到輸入框（同時顯示嘸蝦米碼提示）
- Debug 模式：偏好設定可開啟，記錄操作日誌至 `~/Library/YabomishIM/debug.log`
- 匯入字表改用系統原生選檔對話框

### 修正
- 匯入字表視窗跑到背景、點擊路徑崩潰

### 變更
- App 類型從 LSBackgroundOnly 改為 LSUIElement

---

## [0.2.3] — 2026-03-14

### 修正
- 先按 `'` + 字母不觸發同音字模式
- 同音字 panel 閃一下就消失
- 同音字混合所有讀音（現只取第一個讀音，聲調區分）

### 變更
- 移除 mid-compose `'` 同音字功能
- 同音字組字區顯示注音

---

## [0.2.1] — 2026-03-14

### 新增
- 字表匯入引導：首次啟動偵測空字表 → NSOpenPanel 引導匯入 liu.cin
- 偏好設定新增「匯入字表⋯」按鈕，CINTable 支援熱重載
- 安裝時自動偵測專案根目錄的 liu.cin 並複製到 `~/Library/YabomishIM/`

### 修正
- 切入 toast 改用 `TISNotifySelectedKeyboardInputSourceChanged` 監聯
- 偏好設定「匯入字表⋯」不再因 NSOpenPanel 視窗層級衝突而崩潰

### 變更
- 移除「僅圖示」狀態列選項

---

## [0.2.0] — 2026-03-14

### 新增
- `,,` 命令系統：輸入 `,,` 進入命令模式
  - `,,T` 繁中、`,,S` 簡中、`,,SP` 速打、`,,SL` 慢打
  - `,,TS` 繁→簡、`,,ST` 簡→繁、`,,J` 日文假名
  - `,,RS` 重置字頻、`,,C` 顯示當前模式、`,,H` 命令說明
- `'` 空閒時輸出頓號「、」
- 繁簡轉換表 `t2s.json`/`s2t.json`
- CINTable 新增 `shortestCodesTable`/`longestCodesTable`
- 選字框螢幕偵測：不相容 App 自動 fallback 到固定模式
- 切入 Yabomish 時顯示當前模式 toast
- 固定模式選字框顯示當前模式小標籤
- 偏好設定新增：切入模式提示開關、蝦頭方向、狀態列名稱
- 固定模式右鍵選單新增字體大小調整
- 未知 `,,` 命令顯示 toast 提示

### 修正
- `,,SP`/`,,SL` 等長碼 bug：同一字有多個等長碼時只保留一個
- `,,S` 模式修正：只顯示字表中本身就是簡體的字
- Shift 切回中文 / 注音退出 toast 顯示當前模式
- 游標模式 fallback 改用固定模式顯示

### 變更
- 模式標籤統一：「中」→「繁中」、「簡」→「簡中」

---

## [0.1.20] — 2026-03-13

### 新增
- `/` 穿透模式：空閒時 `/` 直接送給 App
- 同音字尾綴 `'`：打碼中按 `'` 自動送出第一候選字並列出同音字
- 補碼擴充 `r`/`s`/`f`：選第 3/4/5 個候選字

### 變更
- 注音反查觸發改為 `';`（蝦米官方快捷鍵）

### 修正
- 注音鍵盤 ㄣ/ㄥ 對應修正

### 改善
- 同音字結果依萌典字頻排序

---

## [0.1.19] — 2026-03-13

### 變更
- 注音資料回退至純萌典版（9,913 字）

### 修正
- 滿碼（4 碼）無候選字時自動清除

---

## [0.1.18] — 2026-03-13

### 修正
- `[]` 改走 CIN 查表
- 萬用碼結果去重
- `deactivateServer` 清理注音模式與 command buffer 殘留狀態
- `activateServer` 完整重置所有狀態

### 改善
- 字頻每 30 秒自動存檔

---

## [0.1.17] — 2026-03-12

### 修正
- 萬用碼 `*` 被「按住 Shift 暫時英文」攔截
- 萬用碼結果無法用方向鍵翻頁
- 按 `*` 後放開 Shift 誤觸中英切換

### 改善
- 偏好設定調整字體大小後即時生效

---

## [0.1.16] — 2026-03-12

### 變更
- 注音查碼觸發改為 `/zh`（原 `,,z`）
- `/` 開頭進入 command buffer，顯示 marked text

---

## [0.1.15] — 2026-03-12

### 新增
- GUI 偏好設定視窗
- 字體大小可調：游標模式 / 固定模式 / 模式提示

### 變更
- 補碼 `v` 改為選第二候選字

### 移除
- 移除 LLM 相關程式碼

---

## [0.1.14] — 2026-03-12

### 新增
- 中英模式切換時顯示 HUD 提示
- 固定模式選字窗：螢幕底部水平列，半透明毛玻璃風格
- 補碼 `v`：當 v 無法延伸編碼時，快速送出第一候選字

### 修正
- 非數字 selKey 不再造成 crash
- 移除矛盾的 sandbox entitlements
- cursor mode 多螢幕邊界檢查改用正確螢幕

### 改善
- 字頻每 500 次自動 decay（×0.9）
- 萬用碼查詢用 prefix 預過濾
- 選字窗顯示/隱藏加入淡入淡出動畫

---

## [0.1.13] — 2026-03-11

### 新增
- 同音字查詢：送字後按 `'` 進入同音字模式
- 字頻排序加入 bigram 前後文權重（unigram 70% + bigram 30%）

### 改善
- CandidatePanel 改用 label pool 重用
- reverseTable 改為 lazy-build

### 修正
- macOS 安全輸入啟用時自動跳過按鍵處理

---

## [0.1.12] — 2026-03-11

### 修正
- AZERTY 等非 QWERTY 鍵盤佈局下，`activateServer` 強制覆蓋為 ABC 佈局

---

## [0.1.11] — 2026-03-11

### 新增
- `yabomish.sh` 管理工具（編譯、安裝、移除）

### 移除
- 移除 `benchmark.swift`

---

## [0.1.10] — 2026-03-11

初始版本。

- 純 Swift macOS 嘸蝦米輸入法
- 硬體 keyCode 對應
- CIN 字表解析 + 二進位快取
- 萬用碼 `*` 模糊查詢
- 自訂選字窗（NSVisualEffectView 毛玻璃風格）
- 字頻學習（unigram）
- 滿碼自動送字（可選）
- Shift 快按切換中英、按住暫時英文
