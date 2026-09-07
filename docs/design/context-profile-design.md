# 語境系統設計 — 預設 Profile + 編輯器 UI

日期：2026-04-20
狀態：設計完成，待實作

## 一、預設語境 Profile（6 組）

現有 3 組（gn/wk/sc）擴充為 6 組，涵蓋主要使用情境。

| code | icon | 名稱 | inputMode | suggestStrategy | regionVariant | 主要詞庫 |
|------|------|------|-----------|-----------------|---------------|----------|
| `gn` | 💬 | 一般 | t | general | tw | 萌典詞組、成語、NER |
| `wk` | 🏢 | 工作 | t | domain | tw | 晶晶體、商業、資訊 |
| `it` | 💻 | 科技 | t | domain | tw | 資訊、電機、數學 |
| `md` | 🏥 | 醫學 | t | domain | tw | 醫學、動物生態、化學 |
| `sc` | 🇨🇳 | 簡中 | s | general | cn | 中國流行語 |
| `jp` | 🇯🇵 | 日文 | j | general | tw | 日本熟語 |

### 碼的設計邏輯

- 2 字母，語意直覺：gn=general, wk=work, it=IT, md=medical, sc=simplified chinese, jp=japanese
- 保留碼：`xs`（儲存）、`xi`（顯示）
- 使用者自建 profile 可用任意 2 字母（不與上述及保留碼衝突）

### 切換方式

```
,,XGN → 💬 一般
,,XWK → 🏢 工作
,,XIT → 💻 科技
,,XMD → 🏥 醫學
,,XSC → 🇨🇳 簡中
,,XJP → 🇯🇵 日文
,,XS  → 儲存當前設定到 active profile
,,XI  → 顯示當前語境
```

### 各 Profile 詳細設定

#### gn — 一般（日常聊天、一般文書）
```json
{
  "inputMode": "t",
  "suggestEnabled": true,
  "suggestStrategy": "general",
  "charSuggest": true,
  "wordCorpus": "wiki",
  "regionVariant": "tw",
  "fuzzyMatch": true,
  "autoCommit": false,
  "domainOrder": ["domain_phrases", "domain_chengyu", "domain_ner"],
  "domainEnabled": {
    "domain_phrases": true,
    "domain_chengyu": true,
    "domain_ner": true
  }
}
```

#### wk — 工作（辦公室、email、會議）
```json
{
  "inputMode": "t",
  "suggestEnabled": true,
  "suggestStrategy": "domain",
  "charSuggest": true,
  "wordCorpus": "wiki",
  "regionVariant": "tw",
  "fuzzyMatch": true,
  "autoCommit": false,
  "domainOrder": ["domain_jingjing", "domain_biz", "domain_it", "domain_phrases"],
  "domainEnabled": {
    "domain_jingjing": true,
    "domain_biz": true,
    "domain_it": true,
    "domain_phrases": true
  }
}
```

#### it — 科技（寫程式、技術文件）
```json
{
  "inputMode": "t",
  "suggestEnabled": true,
  "suggestStrategy": "domain",
  "charSuggest": true,
  "wordCorpus": "wiki",
  "regionVariant": "tw",
  "fuzzyMatch": true,
  "autoCommit": false,
  "domainOrder": ["domain_it", "domain_ee", "domain_math", "domain_phrases"],
  "domainEnabled": {
    "domain_it": true,
    "domain_ee": true,
    "domain_math": true,
    "domain_phrases": true
  }
}
```

#### md — 醫學（醫療、學術）
```json
{
  "inputMode": "t",
  "suggestEnabled": true,
  "suggestStrategy": "domain",
  "charSuggest": true,
  "wordCorpus": "wiki",
  "regionVariant": "tw",
  "fuzzyMatch": true,
  "autoCommit": false,
  "domainOrder": ["domain_med", "domain_bio", "domain_chem", "domain_phrases"],
  "domainEnabled": {
    "domain_med": true,
    "domain_bio": true,
    "domain_chem": true,
    "domain_phrases": true
  }
}
```

#### sc — 簡中（跟大陸溝通）
```json
{
  "inputMode": "s",
  "suggestEnabled": true,
  "suggestStrategy": "general",
  "charSuggest": true,
  "wordCorpus": "wiki",
  "regionVariant": "cn",
  "fuzzyMatch": true,
  "autoCommit": false,
  "domainOrder": ["domain_cn_slang", "domain_phrases"],
  "domainEnabled": {
    "domain_cn_slang": true,
    "domain_phrases": true
  }
}
```

#### jp — 日文（日文假名輸入）
```json
{
  "inputMode": "j",
  "suggestEnabled": true,
  "suggestStrategy": "general",
  "charSuggest": false,
  "wordCorpus": "wiki",
  "regionVariant": "tw",
  "fuzzyMatch": false,
  "autoCommit": false,
  "domainOrder": ["domain_yoji"],
  "domainEnabled": {
    "domain_yoji": true
  }
}
```

---

## 二、UI Wireframe — 語境編輯器

### 入口：ContextBar（現有，微調）

```
┌─ SuggestionTab ──────────────────────────────────────────────┐
│                                                              │
│  語境切換                                                     │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──┐│
│  │💬一般│ │🏢工作│ │💻科技│ │🏥醫學│ │🇨🇳簡中│ │🇯🇵日文│ │＋││
│  │ [gn] │ │ [wk] │ │ [it] │ │ [md] │ │ [sc] │ │ [jp] │ └──┘│
│  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘      │
│  ,,X + 碼切換                        匯入⋯  匯出⋯           │
│                                                              │
│  右鍵選單：                                                   │
│  ┌────────────┐                                              │
│  │ ✎ 編輯     │                                              │
│  │ 📋 複製    │  ← 複製為新 profile（改名改碼）              │
│  │ 🗑 刪除    │                                              │
│  └────────────┘                                              │
└──────────────────────────────────────────────────────────────┘
```

### 編輯 Sheet

```
┌─ 編輯語境 — 💬 一般 ─────────────────────────────────────────┐
│                                                              │
│  ┌─ 基本 ──────────────────────────────────────────────────┐ │
│  │ 圖示  [💬    ]   名稱  [一般          ]                 │ │
│  │ 命令碼  gn (唯讀)                                        │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌─ 輸入 ──────────────────────────────────────────────────┐ │
│  │ 輸入模式  [繁中      ▾]   地區用詞  [台灣 ▾]           │ │
│  │ 模糊匹配  [✓]              自動送字  [ ]                │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌─ 聯想 ──────────────────────────────────────────────────┐ │
│  │ 聯想系統  [✓]                                           │ │
│  │ 聯想策略  [一般 ▾]         字級聯想  [✓]                │ │
│  │ 詞級語料  [維基百科 ▾]                                   │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌─ 詞庫（拖拉排序 + 開關）───────────────────────────────┐ │
│  │ ☰ [✓] 📖 萌典詞組        教育部辭典                    │ │
│  │ ☰ [✓] 📜 成語            四字成語典故                   │ │
│  │ ☰ [✓] 👤 NER 詞組        人名地名機構                  │ │
│  │ ☰ [ ] 🌐 晶晶體          台式中英夾雜                   │ │
│  │ ☰ [ ] 📊 商業            金融會計管理                   │ │
│  │ ☰ [ ] 💻 資訊            軟體硬體網路                   │ │
│  │        ⋯ (捲動顯示全部 40 個詞庫)                        │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│                              [取消]  [儲存]                   │
└──────────────────────────────────────────────────────────────┘
```

### 互動規則

1. **開啟**：右鍵 profile →「編輯」→ 彈出 sheet
2. **載入**：從 `contexts/{code}.json` 讀取所有欄位
3. **詞庫列表**：已啟用的排上面，未啟用的排下面，可拖拉調整順序
4. **儲存**：寫回 JSON。若為當前 active profile，同時 apply 到 UserDefaults
5. **取消**：不儲存，關閉 sheet
6. **複製**：從右鍵選單觸發，彈出新增 sheet 但預填現有 profile 的值

### 不做的事

- 不做 diff 顯示（過度設計）
- 不做「重設為預設」（使用者可刪除重建）
- 命令碼建立後不可修改（避免 JSON 檔名混亂）

---

## 三、實作估計

| 項目 | 檔案 | 行數 |
|------|------|------|
| 更新預設 profiles | `ContextProfile.swift` | ~30 行 |
| 編輯器 sheet | `ContextProfileEditor.swift`（新增） | ~150 行 |
| ContextBar 加右鍵編輯/複製 | `ContextBar.swift` | ~15 行 |
| 不需要改引擎端 | — | — |
