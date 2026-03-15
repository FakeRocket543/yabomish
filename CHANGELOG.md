# Changelog

所有版本的變更紀錄。格式基於 [Keep a Changelog](https://keepachangelog.com/)。

## [0.2.6] — 2026-03-15

### 新增
- 全型空格：`,,` + Space 或 Shift+Space 送出全型空格（U+3000）
- 字頻同步：偏好設定可指定同步資料夾（如 iCloud Drive），跨機共享字頻學習資料
  - 預設不開啟，首次開啟時自動複製本機 freq.json 到指定資料夾
  - 同步資料夾選擇器支援新增資料夾

### 修正
- 偏好設定視窗前景化：加 `orderFrontRegardless` + 延遲 activate 重試，改善背景 App 視窗跳不出來的問題

### 變更
- 偏好設定 UI 分組：選字窗、輸入、外觀、資料、除錯，加分隔線與小標題

## [0.2.4] — 2026-03-15

### 新增
- 注音模式選字後直接送出字到輸入框（同時顯示嘸蝦米碼提示）
- Debug 模式：偏好設定可開啟，記錄操作日誌至 `~/Library/YabomishIM/debug.log`，方便回報問題
- 匯入字表改用系統原生選檔對話框（osascript），避開背景型 app 視窗層級問題

### 修正
- 匯入字表視窗跑到背景、點擊路徑崩潰：改用外部選檔流程，不再受 InputMethodKit 背景 app 限制
- 偏好設定視窗無法正常前景化：移除 nonactivatingPanel，改為可活化視窗

### 變更
- App 類型從 LSBackgroundOnly 改為 LSUIElement（支援顯示 UI 的 agent app）
- 致謝 GitHub 帳號更正為 [@Marsjelly](https://github.com/Marsjelly)

## [0.2.3] — 2026-03-14

### 修正
- 先按 `'` + 字母不觸發同音字模式（v0.2.0 頓號功能覆蓋）
- 同音字 panel 閃一下就消失（hide 淡出動畫與 show 競爭）
- 同音字混合所有讀音（現只取第一個讀音，聲調區分）

### 變更
- 移除 mid-compose `'` 同音字功能（非官方、bug 來源），只保留送字後 `'` 和先按 `'` 再打碼
- 同音字組字區顯示注音（如 `的[˙ㄉㄜ]`）

## [0.2.1] — 2026-03-14

### 新增
- 字表匯入引導：首次啟動偵測空字表 → NSOpenPanel 引導匯入 liu.cin
- 偏好設定新增「匯入字表⋯」按鈕，CINTable 支援熱重載
- 安裝時自動偵測專案根目錄的 liu.cin 並複製到 `~/Library/YabomishIM/`
- 新增 `Install.command`（DMG 安裝腳本）、`create_dmg.sh`（codesign + notarize 打包）

### 修正
- 切入 toast 改用 `TISNotifySelectedKeyboardInputSourceChanged` 監聽，Cmd+Tab 切 app 不再誤觸
- 偏好設定「匯入字表⋯」不再因 NSOpenPanel 視窗層級衝突而崩潰
- 選 Yabomish 狀態列名稱時未寫回 CFBundleName 的問題

### 變更
- 移除「僅圖示」狀態列選項（會導致切換輸入法浮出框空白），只保留 Yabo / Yabomish
- 模式標籤：繁→簡 / 簡→繁 改為 繁中→簡中 / 簡中→繁中
- `setup.sh` 簡化為一行安裝，移除手動 liu.cin 前置檢查
- README 安裝說明改善：一行指令、Xcode CLT 提示、登出提醒、系統設定搜尋列教學

## [0.2.0] — 2026-03-14

### 新增
- `,,` 命令系統：輸入 `,,`（兩個逗號）進入命令模式，支援以下命令：
  - `,,T` 繁中（預設）、`,,S` 簡中（字表內建簡體字）、`,,SP` 速打（僅最短碼）、`,,SL` 慢打（僅最長碼）
  - `,,TS` 繁中→簡中轉換、`,,ST` 簡中→繁中轉換、`,,J` 日文假名
  - `,,RS` 重置字頻統計、`,,C` 顯示當前模式、`,,H` 命令說明
- `'` 空閒時輸出頓號「、」（`';` 仍觸發注音反查）
- 繁簡轉換表 `t2s.json`（3553 筆）、`s2t.json`（2606 筆），由 OpenCC 生成
- CINTable 新增 `shortestCodesTable` / `longestCodesTable`（支援等長多碼）
- 選字框螢幕偵測：不相容 App（Terminal 等）自動 fallback 到固定模式顯示
- 切入 Yabomish 時顯示當前模式 toast（僅從其他輸入法切入時觸發，以 deactivate 時間差判斷）
- 固定模式選字框顯示當前模式小標籤（非繁中模式時）
- 偏好設定新增：切入模式提示開關、蝦頭方向（← / →）、狀態列名稱（Yabo / Yabomish）
- 固定模式右鍵選單新增字體大小調整（14–48pt）
- 游標模式字體大小上限提高至 48pt（支援 4K+ 螢幕）
- `install.sh` 互動選單：每次安裝可選擇蝦頭方向和狀態列名稱（顯示目前值，Enter 保持）
- 未知 `,,` 命令顯示 toast 提示（含 `,,H` 說明）
- 繁簡轉換表載入失敗時切模式顯示警告 toast

### 修正
- `,,SP` / `,,SL` 等長碼 bug：同一字有多個等長碼時只保留一個，導致部分候選字消失（如「果」有 qtn/rqt）
- `,,S` 模式修正：改為只顯示字表中本身就是簡體的字（原誤與 `,,TS` 相同邏輯）
- 移除 `lastGoodCursorOrigin` 快取，解決多螢幕切換時選字框殘留在錯誤螢幕的問題
- Shift 切回中文 / 注音退出 toast 顯示當前模式（原寫死「繁中」，在簡中等模式下顯示錯誤）
- 游標模式 fallback 改用固定模式顯示（原仍用垂直列表導致位置跳動）
- fallback 固定模式隱藏時加入淡出動畫
- SP/SL 模式提示同碼不重複觸發
- 英文模式下 Shift 組合鍵不再誤觸中英切換（by [@trend-jack-c-tang](https://github.com/trend-jack-c-tang)）
- 游標跟隨模式選字窗定位改善（by [@trend-jack-c-tang](https://github.com/trend-jack-c-tang)）
- `install.sh` 安裝後加 `chmod -R a+rX`（by [@trend-jack-c-tang](https://github.com/trend-jack-c-tang)）

### 變更
- 模式標籤統一：「中」→「繁中」、「簡」→「簡中」（對海外華人更清楚）
- `.gitignore` 加入 `liu.cin`（by [@trend-jack-c-tang](https://github.com/trend-jack-c-tang)）
- `modeLabels` 抽為共用常數，`activeScreen` 加 0.5 秒快取
- 偏好設定視窗高度調整，標籤改為「游標模式字體」/「固定模式字體」
- 移除空的 `punctMap` 死碼

## [0.1.20] — 2026-03-13

### 新增
- `/` 穿透模式：空閒時 `/` 直接送給 App（編輯器 slash command、搜尋、路徑輸入），打碼中仍走 CIN 查表
- 同音字尾綴 `'`：打碼中按 `'` 自動送出第一候選字並列出同音字（原本需先送字再按 `'`）
- 補碼擴充 `r`/`s`/`f`：選第 3/4/5 候選字（原僅 `v` 選第 2 字），無法延伸編碼時觸發

### 變更
- 注音反查觸發改為 `';`（蝦米官方快捷鍵），移除 `/zh` command buffer 系統

### 修正
- 注音鍵盤 ㄣ/ㄥ 對應修正（cerebellum 回報）

### 改善
- 同音字結果依萌典字頻排序（高頻字優先），新增 `char_freq.json`

## [0.1.19] — 2026-03-13

### 變更
- 注音資料回退至純萌典版（9,913 字、1,338 組注音）
  - 曾嘗試合併 Unihan + libchewing 擴充至 43,985 字，但 CJK Extension B+ 罕用字在多數字型無法顯示，同音候選反而不實用

### 修正
- 滿碼（4 碼）無候選字時自動清除（beep + reset），不需手動刪除

### 文件
- README 補注音資料來源說明（萌典 CC BY-ND 3.0 TW）

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
