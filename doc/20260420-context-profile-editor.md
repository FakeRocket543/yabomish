# 語境設定檔管理介面（Context Profile Editor）

日期：2026-04-20
狀態：提案

## 現狀

- **引擎端**：`,,Xxx` 切換語境、`,,XS` 儲存、`,,XI` 顯示
- **設定程式**：`ContextBar`（水平列）可新增/刪除/套用/匯入匯出
- **缺少**：無法在 UI 中細部編輯單一 profile 的各項設定

## 問題

使用者建立語境後，若想修改某個 profile 的設定（例如改詞庫組合、改聯想策略），目前只能：
1. 手動切到該語境 → 在各分頁調整 → `,,XS` 儲存
2. 或刪除重建

沒有「選一個 profile → 直接編輯其欄位」的 UI。

## 提案：ContextProfileEditor

### 入口

在 `ContextBar` 的每個 profile 按鈕上，加入「編輯」選項（右鍵 contextMenu 或雙擊）。
點擊後彈出 sheet，顯示該 profile 的所有可編輯欄位。

### 編輯欄位

| 欄位 | 控件 | 說明 |
|------|------|------|
| name | TextField | 顯示名稱 |
| icon | TextField / Emoji picker | 圖示 |
| code | TextField (唯讀) | 命令碼（建立後不可改） |
| inputMode | Picker | t/s/sp/sl/ts/st/j |
| suggestEnabled | Toggle | 聯想開關 |
| suggestStrategy | Picker | general/domain/off |
| charSuggest | Toggle | 字級聯想 |
| wordCorpus | Picker | wiki/moedict/news |
| regionVariant | Picker | tw/cn |
| fuzzyMatch | Toggle | 模糊匹配 |
| autoCommit | Toggle | 自動送字 |
| domainOrder | 拖拉列表 | 詞庫優先順序 |
| domainEnabled | Toggle 列表 | 各詞庫啟用狀態 |

### UI 結構

```
Sheet: "編輯語境 — 💬 一般"
├── 基本資訊（name, icon）
├── 輸入模式（inputMode, regionVariant）
├── 聯想設定（suggestEnabled, suggestStrategy, charSuggest, wordCorpus）
├── 行為（fuzzyMatch, autoCommit）
└── 詞庫（domainOrder + domainEnabled，可拖拉）
    [儲存] [取消]
```

### 互動流程

1. 右鍵 profile → 「編輯」
2. 彈出 sheet，載入該 profile 的 JSON 欄位
3. 使用者修改 → 按「儲存」
4. 寫入 `~/Library/Application Support/Yabomish/contexts/{code}.json`
5. 如果該 profile 是當前 active 的，同時 apply 到 UserDefaults

### 與現有功能的關係

- `ContextBar` 保持不變（水平切換列）
- 新增的 editor 是 sheet overlay，不影響現有佈局
- `,,XS` 仍然可用（從引擎端快速儲存當前狀態到 active profile）
- Editor 是「精確編輯」，`,,XS` 是「快速快照」

### 額外考慮

- **複製 profile**：從現有 profile 複製一份，改名改碼
- **重設為預設**：把 profile 恢復到 `createDefaults()` 的初始值
- **diff 顯示**：編輯時標示哪些欄位與「當前系統設定」不同

## 工作量估計

- `ContextProfileEditor.swift`：~150 行 SwiftUI
- 修改 `ContextBar.swift`：加 contextMenu 的「編輯」項目，~10 行
- 不需要改引擎端

## 優先級

中。功能完整但非必要——進階使用者才會需要精確編輯單一 profile。
大部分人用 `,,XS` 快照就夠了。
