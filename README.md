# Yabomish

macOS 嘸蝦米輸入法的開源實作，純 Swift、零依賴。

> 本專案不包含嘸蝦米字表，需使用者自行取得 `liu.cin`。

## 特色

### 核心引擎
- 純 Swift，無第三方依賴，shell script 編譯（不需 Xcode 專案）`v0.1.10`
- 硬體 keyCode 對應，不受鍵盤佈局影響（Dvorak、Colemak、AZERTY 等皆可）`v0.1.10` `v0.1.12`
- CIN 字表二進位快取，首次解析後秒開 `v0.1.10`
- 安全輸入偵測（密碼欄位自動停用）`v0.1.13`

### 選字窗
- 兩種模式：游標跟隨（預設）/ 固定位置 `v0.1.10` `v0.1.14`
  - **游標跟隨** — 毛玻璃垂直列表，跟著輸入位置走
  - **固定位置** — 螢幕底部水平列，可上下拖曳、右鍵調整對齊/透明度
- 多螢幕支援，自動偵測正確螢幕 `v0.1.14`
- 顯示/隱藏淡入淡出動畫 `v0.1.14`

### 輸入功能
- 萬用碼 `*` 模糊查詢（prefix 預過濾加速）`v0.1.10` `v0.1.14`
- 補碼 `v`/`r`/`s`/`f` 快速選第 2–5 候選字（無法延伸編碼時）`v0.1.14` `v0.1.20`
- 滿碼自動送字（可選）`v0.1.10`
- `/` 穿透：空閒時直送 App（編輯器 slash command），打碼中仍走 CIN `v0.1.20`
- 中文標點：`[]` `[[` `]]` 走 CIN 查表（「」『』【】《》等）、`,` → ， `v0.1.18`
- Shift 快按切換中英、按住暫時英文 `v0.1.10`
- 中英模式切換 HUD 提示（「中」/「A」）`v0.1.14`

### 查詢功能
- 同音字查詢：按 `'` 進入同音字模式，選字後列出所有同音字 `v0.1.13`
  - 打碼中按 `'` 可直接送出第一候選並列同音字（不需先送字）`v0.1.20`
- 注音反查：`';` 切換注音查碼模式（蝦米官方快捷鍵），輸入注音查嘸蝦米碼
  - 聲韻母可任意順序輸入，自動排列至正確 slot

### 智慧排序
- 字頻學習：unigram + bigram 前後文排序 `v0.1.10` `v0.1.13`
- 每 500 次自動 decay（×0.9）防膨脹 `v0.1.14`

### 設定介面
- GUI 偏好設定視窗（從輸入法選單開啟）`v0.1.15`
- 字體大小可調：游標模式 / 固定模式 / 模式提示 `v0.1.15`

## 需求

- macOS 14.0+（Apple Silicon）
- Xcode Command Line Tools（`xcode-select --install`）
- 嘸蝦米 CIN 字表（`liu.cin`）

## 安裝

打開「終端機」（應用程式 → 工具程式 → 終端機），依序貼上：

```bash
# 1. 下載專案
git clone https://github.com/AlohaYos/yabomish.git
cd yabomish

# 2. 將你的 liu.cin 複製到這個資料夾
cp /你的liu.cin路徑/liu.cin .

# 3. 一鍵安裝（自動檢查編譯工具、編譯、安裝）
./setup.sh
```

安裝完成後，到 **系統設定 → 鍵盤 → 輸入方式 → 點左下角「+」** 加入「Yabomish」。

## 使用

### 基本操作

| 操作 | 按鍵 |
|------|------|
| 送字 | 空白鍵 |
| 選字 | 1–9, 0（或字表自訂 selKey） |
| 萬用碼 | `*` |
| 補碼選字 | `v`/`r`/`s`/`f`（第 2–5 候選） |
| 同音字 | `'`（送字後）或碼尾加 `'` |
| 刪碼 | Backspace |
| 清除 | Esc |
| 直送英文 | Enter |
| 直送 `/` | `/`（空閒時穿透給 App） |
| 中英切換 | 快按 Shift |
| 暫時英文 | 按住 Shift |
| 翻頁 | Tab / PageDown / PageUp |
| 注音反查 | `';` 切換 |

### 中文標點

| 按鍵 | 輸出 |
|------|------|
| `,`（單按） | ， |
| `[` | CIN 查表（「、（、﹁、【⋯） |
| `[[` | CIN 查表（『、﹃、【、《⋯） |
| `]]` | CIN 查表（』、﹄、】、》⋯） |

### 同音字查詢

1. 方法一：送字後按 `'`，直接列出該字的所有同音字
2. 方法二：打碼中按 `'`（如 `abc'`），送出第一候選並列同音字
3. 方法三：先按 `'` 進入同音字模式，輸入碼選字後列出同音字
4. ↑↓ 移動、←→ 翻頁、Enter 確認（固定模式：←→ 移動、↑↓ 翻頁）

### 注音反查

1. 輸入 `';` 進入注音查碼模式（顯示「注」提示）
2. 按注音鍵盤輸入注音符號（聲母、介音、韻母可任意順序，自動排列）
3. 按聲調鍵（3=ˇ 4=ˋ 6=ˊ 7=˙）或空白鍵（一聲）送出查詢
4. 選字窗顯示對應漢字及嘸蝦米碼
5. 再按 `';` 或 Esc（空 buffer 時）回到一般模式

### 選字窗模式

**游標跟隨**（預設）— 選字窗出現在輸入游標旁。部分 App（Terminal、某些 Electron App）無法正確回報游標位置，會自動 fallback 到上次有效位置或螢幕底部。

**固定位置** — 選字窗固定在螢幕底部，顯示為水平列。←→ 選字、↑↓ 翻頁。可以：
- 上下拖曳調整位置
- 右鍵選單切換對齊方式（靠左/置中/靠右）
- 右鍵選單調整透明度

## 設定

點選選單列的輸入法圖示，選擇「偏好設定⋯」開啟設定視窗，可調整：

- 選字窗模式（游標跟隨 / 固定位置）
- 對齊方式（固定模式）
- 透明度
- 字體大小（游標模式 / 固定模式 / 模式提示）
- 滿碼自動送字

也可用 `defaults write` 指令：

```bash
# 選字窗固定在螢幕底部
defaults write com.yabomishim.inputmethod.YabomishIM panelPosition fixed

# 選字窗跟隨游標（預設）
defaults write com.yabomishim.inputmethod.YabomishIM panelPosition cursor

# 滿碼自動送字
defaults write com.yabomishim.inputmethod.YabomishIM autoCommit -bool true

# 固定模式對齊：center / left / right
defaults write com.yabomishim.inputmethod.YabomishIM fixedAlignment center

# 固定模式透明度（0.3–1.0）
defaults write com.yabomishim.inputmethod.YabomishIM fixedAlpha -float 0.85

# 字體大小
defaults write com.yabomishim.inputmethod.YabomishIM fontSize -float 16
defaults write com.yabomishim.inputmethod.YabomishIM fixedFontSize -float 18
defaults write com.yabomishim.inputmethod.YabomishIM toastFontSize -float 36
```

## 更新

```bash
cd yabomish
git pull
./setup.sh
```

## 資料路徑

所有使用者資料存放在 `~/Library/YabomishIM/`：

| 檔案 | 說明 |
|------|------|
| `liu.cin` | 嘸蝦米字表（使用者提供） |
| `liu.cin.cache` | 二進位快取（自動產生，字表更新時自動重建） |
| `freq.json` | 字頻學習資料（自動產生） |
| `zhuyin_data.json` | 注音對照表（內建於 App bundle，可自行覆蓋） |

App 載入順序：先找 `~/Library/YabomishIM/` 下的檔案，找不到才用 App bundle 內建版本。更換字表只需替換 `~/Library/YabomishIM/liu.cin`，無需重新編譯。

## 架構

```
YabomishIM/
├── Sources/
│   ├── AppDelegate.swift              # IMKServer 啟動
│   ├── YabomishInputController.swift  # 輸入控制器（按鍵處理、狀態機）
│   ├── CINTable.swift                 # CIN 字表解析、快取、萬用碼查詢
│   ├── CandidatePanel.swift           # 選字窗（游標/固定雙模式）
│   ├── FreqTracker.swift              # 字頻學習（unigram + bigram + decay）
│   ├── ZhuyinLookup.swift             # 注音反查 + 同音字查詢
│   ├── Prefs.swift                    # UserDefaults 偏好設定
│   └── PrefsWindow.swift              # GUI 偏好設定視窗
├── Resources/
│   ├── Info.plist
│   ├── zhuyin_data.json
│   ├── icon.icns / icon.tiff
│   └── YabomishIM.entitlements
├── build.sh                           # 編譯腳本
└── install.sh                         # 安裝腳本
```

## 版本歷程

| 版本 | 日期 | 重點 |
|------|------|------|
| 0.1.20 | 2026-03-13 | `/` 穿透模式、同音字尾綴 `'`、補碼 VRSF |
| 0.1.19 | 2026-03-13 | 注音資料回退至純萌典版（9913 字）、滿碼無候選自動清除 |
| 0.1.18 | 2026-03-13 | `[]` 走 CIN 查表、萬用碼去重、狀態清理修正、字頻定期存檔 |
| 0.1.17 | 2026-03-12 | 萬用碼 `*` 修正、方向鍵選字通用化、字體大小即時生效 |
| 0.1.16 | 2026-03-12 | `/zh` 取代 `,,z` 觸發注音查碼；逗號還給 CIN 編碼（1737 筆恢復） |
| 0.1.15 | 2026-03-12 | GUI 偏好設定視窗、字體大小可調、移除 LLM 程式碼 |
| 0.1.14 | 2026-03-12 | 固定位置選字窗、HUD 模式提示、字頻 decay、多螢幕修正 |
| 0.1.13 | 2026-03-11 | 同音字查詢、bigram 字頻、效能優化 |
| 0.1.12 | 2026-03-11 | AZERTY 鍵盤佈局修正 |
| 0.1.11 | 2026-03-11 | setup.sh 一鍵安裝 |
| 0.1.10 | 2026-03-11 | 初始版本 |

> 後續更新：注音查碼重構（slot 自動排列 + 聲調修復）、中文標點直出、固定模式方向鍵選字修正。詳見 [CHANGELOG.md](CHANGELOG.md)。

## 支持作者

覺得好用？來吃一球 gelato 🍨
[Golden Rooster](https://shop.goldenrooster.tw)

## 注音資料來源

內建 `zhuyin_data.json` 取自 [g0v/moedict-data](https://github.com/g0v/moedict-data)（教育部《重編國語辭典修訂本》，CC BY-ND 3.0 TW），涵蓋 9,913 字、1,338 組注音。

曾嘗試合併 [Unihan](https://www.unicode.org/reports/tr38/) 與 [libchewing](https://github.com/chewing/libchewing) 擴充至 43,985 字，但新增的大量 CJK Extension B+ 罕用字在多數字型中無法顯示，同音候選反而不實用，因此回退至純萌典版本。

## 授權

MIT
