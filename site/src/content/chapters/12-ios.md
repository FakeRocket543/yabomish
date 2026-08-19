---
title: "iOS 版"
order: 12
---

Yabomish 的 iOS 版本與 macOS 共用同一套輸入引擎與設定契約，最大的差異是安全模型：**iOS 鍵盤擴充以「零權限」為設計目標**。

---

## 12.1 安裝與啟用

1. 在 iPhone 上安裝 Yabomish App
2. 開啟 **設定 → 一般 → 鍵盤 → 鍵盤 → 新增鍵盤**，選擇 Yabomish
3. 完成——**不需要**開啟「允許完整存取」

App 內首頁可匯入 `.cin` 字表檔（與 macOS 同格式）。

---

## 12.2 零權限設計

Yabomish 鍵盤**不要求完整存取（Full Access）**。在鍵盤設定頁，你不會看到「允許完整存取」開關，也不會看到「按鍵可供開發者取得」的警告。

這代表：

- 鍵盤擴充**零網路**——無法把任何資料送出裝置
- 鍵盤不會出現在隱私敏感場景的風險清單
- 密碼欄位（系統行為）與銀行類 App 自動改用系統鍵盤

所有核心功能（打字、字表、候選、聯想、snippet 展開）都在無網路環境下運作。實測飛航模式可完整使用。

### 技術原理

iOS 對無 Full Access 的鍵盤開放 App Group 共容器的**唯讀**存取。Yabomish 讓鍵盤只讀設定（字表、commands.json、snippet），需要寫入的資料（學習頻率、除錯記錄）改存鍵盤自有的沙盒容器，並在權限狀態變更時自動合併——你的打字學習不會因為權限設定而遺失。

---

## 12.3 跨裝置同步

macOS 與 iOS 之間透過 S3 相容儲存（R2 / OVH 等）同步：

- **同步內容**：`commands.json`、`char_freq.json`、`user_snippets.json`、語境設定（`contexts/`）
- **操作位置**：iOS App 內「跨裝置同步」頁；macOS 用 `yabomish-sync` 指令
- **憑證保存**：endpoint、bucket、access key 存在 iOS Keychain，只在容器 App 內使用——鍵盤擴充全程不碰網路

同步策略為快照 + last-writer-wins，兩端以 manifest 校驗檔案完整性。

---

## 12.4 Hermes 詢問（App 內）

如果你在本機跑 Hermes agent listener（預設 `http://127.0.0.1:8765/ask`），iOS App 提供「Hermes 詢問」頁：

1. 列出 `commands.json` 中所有 `type: "hermes"` 條目
2. 點擊即送出該條目的 `send` 字串
3. 回覆顯示在頁面中，可一鍵複製

與 macOS 的 `,,ask` 使用同一份設定檔（見 7.4 節）。同樣僅允許本機位址——惡意同步的設定無法把請求導向外部伺服器。

> 注意：iOS 鍵盤內無法直接觸發 Hermes（鍵盤零網路是刻意設計）。Hermes 詢問在容器 App 內進行，回覆靠複製貼上帶入。

---

## 12.5 與 macOS 的對照

| 功能 | macOS | iOS |
|------|-------|-----|
| 打字 / 字表 / 聯想 | ✅ | ✅ |
| `text` 型 snippet 展開 | ✅ | ✅ |
| `shell` / `open` 型指令 | ✅ | ❌（沙盒限制） |
| Hermes 橋接 | 輸入法內 `,,ask` 直插游標 | App 內詢問頁 |
| 跨裝置同步 | `yabomish-sync` | App 內同步頁 |
| 學習資料合併 | iCloud / sync | 權限翻轉自動吸收 |
