---
title: "資料與檔案"
order: 9
---

---

## 資料路徑

Yabomish 的所有使用者資料存放於：

```
~/Library/YabomishIM/
├── liu.cin                    # 嘸蝦米字表（使用者匯入）
├── liu.bin                    # 編譯後二進位字表（mmap zero-copy）
├── freq.db                    # 字頻學習資料（SQLite WAL）
├── tables/                    # 擴充表資料夾
│   └── user_shortcuts.txt     # 使用者快捷碼
├── user_phrases.txt           # 使用者自訂詞組
└── debug.log                  # Debug 日誌（開啟時才產生）
```

各檔案說明：

| 檔案 | 說明 |
|------|------|
| `liu.cin` | 使用者自行取得的嘸蝦米 CIN 字表原始檔。透過設定程式匯入。 |
| `liu.bin` | 由 `liu.cin` 在裝置上編譯而成的二進位格式。採用 mmap zero-copy 載入，啟動極快。 |
| `freq.db` | SQLite 資料庫，記錄 unigram、bigram、trigram 字頻。使用 WAL 模式，每 500 次自動 decay。 |
| `tables/` | 擴充表資料夾。安裝時預設包含 Emoji 聯想表。可自行新增 tab-separated 格式的 `.txt` 檔。 |
| `user_shortcuts.txt` | 空碼快捷碼綁定，由設定程式的「快捷碼」分頁管理。 |
| `user_phrases.txt` | 使用者自訂詞組。 |
| `debug.log` | 開啟 Debug 模式後產生的日誌檔。 |

> **提示**：修改擴充表後，輸入 `,,RL` + 空白鍵即可即時重載，不需重新啟動。

---

## 語料架構

Yabomish 的語料分為四層，由底層到高層依序為：

```
┌─────────────────────────────────────────────────────────┐
│  Layer 3  詞庫                                          │
│           12 一般詞庫 + 28 專業詞典                      │
│           + 兩岸用詞標記 + 晶晶體（中英夾雜）            │
├─────────────────────────────────────────────────────────┤
│  Layer 2  詞級語料                                      │
│           萌典（教育部辭典）/ 維基百科斷詞 / 新聞斷詞     │
├─────────────────────────────────────────────────────────┤
│  Layer 1  字頻 + bigram + trigram                       │
│           使用者學習（SQLite）+ 靜態統計                  │
├─────────────────────────────────────────────────────────┤
│  Layer 0  CIN 字表                                      │
│           嘸蝦米碼 → 字（核心對應表）                     │
└─────────────────────────────────────────────────────────┘
```

- **Layer 0**：最基礎的編碼對應。使用者匯入 `liu.cin` 後編譯為 `liu.bin`。
- **Layer 1**：排序依據。unigram 字頻由使用者打字習慣累積，bigram/trigram 提供前後文預測。權重為 70% unigram + 30% bigram。
- **Layer 2**：聯想輸入的詞級來源。可在設定程式中切換萌典、維基百科斷詞、新聞斷詞三種語料。
- **Layer 3**：最上層的詞庫系統。包含一般詞庫（成語、歇後語、台灣俗諺、客語辭典、台灣地名、學科術語、韓語漢字詞、日本熟語等 13 類）和 28 個專業詞典（資訊、商業、醫學、法律等，資料來源為樂詞網 NAER 及維基百科）。兩岸用詞標記可依使用者偏好降權對側用詞。晶晶體為獨立聯想池。

三層聯想的順序可在設定程式中拖拉調整。


---

## 二進位格式

所有語料以自訂二進位格式儲存，統一採用 **mmap zero-copy** 載入，查詢時間複雜度為 **O(log n)**。

| 格式代碼 | 用途 | 說明 |
|----------|------|------|
| `CINM` | CIN 字表 | 嘸蝦米碼 → 字的核心對應表 |
| `WBMM` | 詞庫 | word bigram / domain terms（一般詞庫與專業詞典） |
| `TGMM` | trigram | 三元組統計，複合鍵 `prev2\|prev1` 存入 |
| `BGMM` | bigram | 二元組統計，字級聯想建議 |
| `NRMM` | NER phrases | 命名實體詞組（人名、地名、組織名等） |
| `PHMM` | phrase dictionary | 詞組辭典 |

這些二進位檔由 `tools/` 目錄下的 Python pipeline 從原始語料建置而成。使用者不需手動處理——安裝時會自動從 GitHub Release 下載預建語料。

> **設計理念**：mmap 讓作業系統按需載入頁面，實際佔用的實體記憶體遠小於檔案大小。這也是 Yabomish 雖載入大量語料，記憶體佔用卻僅約 70MB 的原因。

---

## 資料來源與授權

| 資料 | 來源 | 授權 |
|------|------|------|
| 注音對照表 | [威注音 VanguardLexicon](https://atomgit.com/vChewing/vChewing-VanguardLexicon) | MIT |
| 繁簡對照表 | [OpenCC](https://github.com/BYVoid/OpenCC) | Apache 2.0 |
| 成語 | 教育部成語典 | 政府開放資料 |
| 台灣俗諺 | [教育部台灣閩南語常用詞辭典](https://sutian.moe.edu.tw/) | 政府開放資料 |
| 客語辭典 | [教育部臺灣客語辭典](https://hakkadict.moe.edu.tw/)（六腔） | 政府開放資料 |
| 台灣地名 | [教育部本土語言標注臺灣地名](https://language.moe.gov.tw/) | CC-BY 3.0 TW |
| 台語學科 | [教育部臺灣台語學科術語](https://stti.moe.edu.tw/) | CC-BY 3.0 TW |
| 兩岸用詞對照 | [國家教育研究院 樂詞網](https://terms.naer.edu.tw/) | 政府開放資料 |
| 專業詞典 ×28 | [國家教育研究院 樂詞網](https://terms.naer.edu.tw/) | 政府開放資料 |
| 歇後語 | [chinese-xinhua](https://github.com/pwxcoo/chinese-xinhua) | MIT |
| 韓語漢字詞 | [Kengdic](https://github.com/garfieldnate/kengdic) | MPL 2.0 / LGPL 2.0+ |
| 維基語料 | 中文維基百科 zhwiki dump | CC-BY-SA 3.0 |
| 新聞詞頻 | 國家教育研究院 新聞語料庫 | 政府開放資料 |
| 萌典字頻 | [萌典](https://www.moedict.tw/) | CC0 |
| Emoji | [Unicode CLDR](https://cldr.unicode.org/) | Unicode License |

明碼語料及各自的授權、格式、build 指令詳見 `yabomish_data/README.md`。

---

## 程式碼授權

Yabomish 程式碼以 **MIT License** 授權釋出。

嘸蝦米字表（`liu.cin`）為使用者自行取得，不包含在本專案中。

---
