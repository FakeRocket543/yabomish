# Changelog

所有版本的變更紀錄。格式基於 [Keep a Changelog](https://keepachangelog.com/)。

## [0.1.19] — 2026-03-13

### 新增
- 注音資料擴充：整合萌典 + Unihan + libchewing，9,913 → 43,985 字
- 滿碼（4 碼）無候選字時自動清除（beep + reset），不需手動刪除

### 文件
- README 補注音資料來源說明

## [0.1.18] — 2026-03-13

### 修正
- `[]` 改走 CIN 查表，支援 `[[` `]]` 等多碼括號（原 hardcode 攔截導致無法輸入）
- 萬用碼結果去重（多碼匹配同一字時不再重複顯示）
- `deactivateServer` 清理注音模式與 command buffer 殘留狀態
- `activateServer` 完整重置所有狀態（同音字、command buffer、注音 slots）
- 偏好設定注音反查說明文字 `,,z` → `/zh`

### 改善
- 字頻每 30 秒自動存檔（防止 crash 丟失學習資料）
- 固定模式選字窗加最大寬度限制（85% 螢幕寬）

## [0.1.17] — 2026-03-12

### 修正
- 萬用碼 `*`（Shift+8）被「按住 Shift 暫時英文」攔截，無法使用
- 萬用碼結果無法用方向鍵翻頁選字（方向鍵改為所有候選字面板通用）
- 按 `*` 後放開 Shift 誤觸中英切換

### 改善
- 偏好設定調整字體大小後即時生效（不需重新登入）

## [0.1.16] — 2026-03-12

### 變更
- 注音查碼觸發改為 `/zh`（原 `,,z`），逗號還給 CIN 正常編碼
  - 1737 筆逗號開頭編碼恢復（方向鍵 `,z`、希臘字母、注音符號等）
  - `/` 開頭進入 command buffer，顯示 marked text，Backspace 可刪、Enter 取消

## [0.1.15] — 2026-03-12

### 新增
- GUI 偏好設定視窗（`PrefsWindow.swift`），從輸入法選單「偏好設定⋯」開啟
- 字體大小可調：游標模式 / 固定模式 / 模式提示（`fontSize`、`fixedFontSize`、`toastFontSize`）

### 變更
- 補碼 `v` 改為選第二候選字（原為第一候選字）

### 移除
- 移除 LLM 相關程式碼（LLMClient、,,l toggle、Tab accept、daemon 連線）
- 移除偏好設定快捷鍵（Cmd+,），避免與前景 App 衝突

## [0.1.14] — 2026-03-12

### 新增
- 中英模式切換時顯示 HUD 提示（「中」/「A」），0.6 秒後淡出
- 固定模式選字窗：螢幕底部水平列，半透明毛玻璃風格
  - 可上下拖曳調整位置
  - 右鍵選單：切換對齊（靠左/置中/靠右）、調整透明度、切換模式
  - 偏好設定：`fixedAlignment`、`fixedAlpha`、`fixedYOffset`
- 補碼 `v`：當 v 無法延伸編碼時，快速送出第一候選字

### 修正
- 非數字 selKey（如 `asdfghjkl;`）不再造成 crash（改用全形數字顯示鍵位）
- 移除矛盾的 sandbox entitlements（`YabomishIM.entitlements`）
- cursor mode 多螢幕邊界檢查改用正確螢幕（`targetScreen`）

### 改善
- 字頻每 500 次自動 decay（×0.9），防止 `freq.json` 無限膨脹
- 萬用碼查詢用 prefix 預過濾，減少全表掃描
- 選字窗顯示/隱藏加入淡入淡出動畫（固定模式）
- 螢幕參數變更時自動重新定位（固定模式）

## [0.1.13] — 2026-03-11

### 新增
- 同音字查詢：送字後按 `'` 進入同音字模式，列出所有同音字
  - ↑↓ 移動、←→ 翻頁、Enter 確認
  - 新增 `ZhuyinLookup.swift` 模組 + `zhuyin_data.json` 注音對照表
- 字頻排序加入 bigram 前後文權重（unigram 70% + bigram 30%）

### 改善
- CandidatePanel 改用 label pool 重用，不再每次重建（效能提升）
- reverseTable 改為 lazy-build，僅在首次 reverseLookup 時建立
- 游標位置 fallback：App 回報 NSRect.zero 時使用上次有效位置

### 修正
- macOS 安全輸入啟用時（密碼欄位）自動跳過按鍵處理

## [0.1.12] — 2026-03-11

### 修正
- AZERTY 等非 QWERTY 鍵盤佈局下，`activateServer` 強制覆蓋為 ABC 佈局，確保 keyCode 對應正確

## [0.1.11] — 2026-03-11

### 新增
- `setup.sh` 一鍵安裝腳本（檢查 Xcode CLT → 複製字表 → 編譯 → 安裝）

### 移除
- 移除 `benchmark.swift`

## [0.1.10] — 2026-03-11

初始版本。

- 純 Swift macOS 嘸蝦米輸入法
- 硬體 keyCode 對應，不受鍵盤佈局影響
- CIN 字表解析 + 二進位快取
- 萬用碼 `*` 模糊查詢
- 自訂選字窗（NSVisualEffectView 毛玻璃風格）
- 字頻學習（unigram）
- 滿碼自動送字（可選）
- Shift 快按切換中英、按住暫時英文
- `build.sh` / `install.sh` 編譯安裝腳本
