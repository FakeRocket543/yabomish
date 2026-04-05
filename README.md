# Yabomish

macOS 嘸蝦米輸入法 — 純 Swift、零依賴、知識增強。

## 特色

### 核心引擎
- **硬體 keyCode 對應** — Dvorak、Colemak、AZERTY 等非 QWERTY 鍵盤正常運作
- **CIN 字表二進位快取** — 首次解析後秒開
- **安全輸入偵測** — 密碼欄位自動停用

### 選字窗
- **游標跟隨模式** — 毛玻璃垂直列表
- **固定位置模式** — 水平列，可拖曳、右鍵調整對齊/透明度
- **多螢幕支援** — GPU 終端無效座標時自動 fallback
- **全螢幕 App 相容** — cmux/Ghostty 中正常顯示

### 輸入模式（`,,` 命令系統）

| 命令 | 模式 |
|------|------|
| `,,T` | 繁中（預設） |
| `,,S` | 簡中（字表內建簡體字） |
| `,,SP` | 速打（僅最短碼） |
| `,,SL` | 慢打（僅最長碼） |
| `,,TS` | 繁→簡轉換 |
| `,,ST` | 簡→繁轉換 |
| `,,J` | 日文假名 |
| `,,PYS` | 拼音查碼（簡體字＋簡體碼） |
| `,,PYT` | 拼音查碼（繁體字＋繁體碼） |
| `,,ZH` | 注音查碼模式 |
| `,,TO` | 同音字查詢模式 |
| `,,RS` | 重置字頻統計 |
| `,,RL` | 重載字表＋擴充表 |
| `,,C` | 顯示當前模式 |
| `,,H` | 命令說明 |

### 擴充表系統
- `~/Library/YabomishIM/tables/*.txt` — tab-separated `編碼<Tab>內容`
- 支援 iCloud 同步資料夾共用
- 安裝時預設 `emoji.txt`（1,906 個 emoji，`em` 開頭五碼）

### 查詢功能
- **同音字查詢** — 按 `'` 列出所有同音字，依威注音權重排序
- **注音反查** — `';` 切換，輸入注音查嘸蝦米碼
- **拼音查碼** — 輸入拼音字母＋聲調數字（空白＝一聲）

### 智慧排序
- **Unigram** — 字頻學習
- **Bigram** — 前後文權重（70% unigram + 30% bigram）
- **Trigram 聯想** — 自動建議下一個字（虛詞結尾停止，標點結尾停止）
- **Wiki N-gram** — 維基語料訓練的語言模型加權
- **NER 詞組** — 知識圖譜實體查詢
- **社群上下文** — 自動偵測輸入領域並加權

### 輸入功能
- **萬用碼** `*` — prefix 預過濾加速
- **補碼** `v`/`r`/`s`/`f` — 選第 2–5 候選字
- **滿碼自動送字** — 可選
- **`/` 穿透** — 空閒時直送 App（slash command）
- **`'` 輸出頓號** — 空閒時
- **全型空格** — ``,` + Space 或 Shift+Space
- **Shift 快按** — 中英切換
- **Shift 按住** — 暫時英文

### 設定
- GUI 偏好設定視窗（從輸入法選單開啟）
- 字體大小可調：游標模式 / 固定模式 / 模式提示
- 滿碼自動送字、拆碼提示、注音反查、切入模式提示
- 蝦頭方向、狀態列名稱（Yabo / Yabomish）
- 字頻 iCloud 同步資料夾
- Debug 模式（日誌寫入 `~/Library/YabomishIM/debug.log`）

## 需求

- macOS 14.0+ (Apple Silicon)
- Xcode Command Line Tools
- 嘸蝦米 CIN 字表（`liu.cin`，使用者自行取得）

## 安裝

```bash
git clone https://github.com/FakeRocket543/yabomish.git && cd yabomish && ./setup.sh
```

安裝完成後：
1. **登出再登入**
2. 系統設定 → 搜尋「Yabomish」→ 輸入方式 → 加入
3. 首次切換會引導選擇 `liu.cin`

### 手動匯入字表

偏好設定 → 匯入字表⋯ → 選擇 `liu.cin`

## 使用

### 基本操作

| 操作 | 按鍵 |
|------|------|
| 送字 | 空白鍵 |
| 選字 | 1–9, 0（或字表 selKey） |
| 萬用碼 | `*` |
| 補碼 | `v`/`r`/`s`/`f` |
| 同音字 | `'` |
| 頓號 | `'`（空閒時） |
| 模式切換 | `,,` + 命令碼 + 空白鍵 |
| 注音查碼 | `';` |
| 全型空格 | ``,` + Space / Shift+Space |
| 中英切換 | 快按 Shift |
| 暫時英文 | 按住 Shift |

### 擴充表格式

```
emfgf	😀
ccrev	Review this code for bugs and improvements:
```

新增/修改後打 `,,RL` 即時重載。

## 移除

```bash
cd yabomish && ./uninstall.sh
```

## 資料路徑

`~/Library/YabomishIM/`：

| 檔案 | 說明 |
|------|------|
| `liu.cin` | 嘸蝦米字表 |
| `liu.cin.cache` | 二進位快取 |
| `freq.json` | 字頻學習資料 |
| `tables/*.txt` | 擴充表 |
| `yabomish_ime.db` | 知識圖譜資料庫 |
| `debug.log` | Debug 日誌（開啟時） |

## 架構

```
YabomishIM/Sources/
├── AppDelegate.swift              # IMKServer 啟動
├── YabomishInputController.swift  # 輸入控制器（按鍵處理、狀態機）
├── CINTable.swift                 # CIN 字表解析、快取、萬用碼
├── CandidatePanel.swift           # 選字窗（游標/固定雙模式）
├── FreqTracker.swift              # 字頻學習（unigram + bigram + decay）
├── ZhuyinLookup.swift             # 注音反查 + 同音字查詢
├── PhraseLookup.swift             # NER 詞組 + 社群上下文（SQLite）
├── Prefs.swift                    # UserDefaults 偏好設定
├── PrefsWindow.swift              # GUI 偏好設定視窗
└── DebugLog.swift                 # Debug 日誌
```

## 知識挖掘 Pipeline

```
tools/
├── wiki_ngram_pipeline.py    # 維基 → ckip 斷詞 → n-gram 統計
├── wiki_ner_pipeline.py      # 維基 → ckip NER → 實體抽取
├── wiki_kg_pipeline.py       # NER × 條目標題 → 知識圖譜
├── build_ime_db.py           # 組裝 → yabomish_ime.db
└── ime_prototype.py          # 三層排序引擎原型測試
```

## 資料來源

- **注音對照表** — 威注音輸入法 [VanguardLexicon](https://atomgit.com/vChewing/vChewing-VanguardLexicon)（MIT）
- **繁簡對照表** — [OpenCC](https://github.com/BYVoid/OpenCC)（Apache 2.0）

## 授權

MIT
