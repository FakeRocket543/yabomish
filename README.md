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
  - **固定位置** — 螢幕底部水平列，可上下拖曳、右鍵調整對齊/透明度/字體大小
- 多螢幕支援，自動偵測正確螢幕 `v0.1.14` `v0.2.0`
  - 不相容 App（Terminal 等）自動 fallback 到固定模式顯示
- 非預設模式時選字框顯示模式小標籤（如 [簡中]、[速]、[日]）`v0.2.0`
- 顯示/隱藏淡入淡出動畫 `v0.1.14`

### 輸入模式（`,,` 命令系統）`v0.2.0`

輸入 `,,`（兩個逗號）進入命令模式，再輸入命令碼 + 空白鍵切換：

| 命令 | 模式 | 說明 |
|------|------|------|
| `,,T` | 繁中 | 預設模式 |
| `,,S` | 簡中 | 只顯示字表中本身就是簡體的字 |
| `,,SP` | 速打 | 只接受最短碼（練習用） |
| `,,SL` | 慢打 | 只接受最長碼（練習用） |
| `,,TS` | 繁→簡 | 打繁體碼，輸出簡體字 |
| `,,ST` | 簡→繁 | 打簡體碼，輸出繁體字 |
| `,,J` | 日文 | 假名輸入（碼+`,`=平假名、碼+`.`=片假名） |
| `,,PYS` | 拼音查碼 | 輸入拼音查簡體字＋簡體碼（聲調 1-5，空白=一聲） |
| `,,PYT` | 拼音查碼 | 輸入拼音查繁體字＋繁體碼（聲調 1-5，空白=一聲） |
| `,,ZH` | — | 切換注音查碼模式（同 `';`） |
| `,,TO` | — | 進入同音字查詢模式（同先按 `'`） |
| `,,RS` | — | 重置字頻統計（候選字順序跑掉時使用） |
| `,,RL` | — | 重載字表 + 擴充表 |
| `,,C` | — | 顯示當前模式 |
| `,,H` | — | 顯示命令說明 |

### 擴充表 `v0.2.10`

在 `~/Library/YabomishIM/tables/` 放入 `.txt` 檔即可擴充字表，格式為 tab-separated：

```
emfgf	😀
ccrev	Review this code for bugs and improvements:
```

- 安裝時預設包含 `emoji.txt`（1,906 個 emoji，`em` + 分類碼 + 2 字母，共 5 碼）
- 附帶 `prompts-example.txt` 範例，可自行改名為 `prompts.txt` 使用
- 新增/修改後打 `,,RL` 即時重載，不需重新登入
- 偏好設定可「匯入字表」或「編輯擴充表」
- 如已設定同步資料夾，該路徑下的 `tables/` 也會自動載入

#### Emoji 分類

| 前綴 | 分類 | 範例 |
|------|------|------|
| `emf` | 表情 | `emfgf` → 😀 |
| `emp` | 人物 | `empni` → 🥷 |
| `ema` | 動物自然 | `emadf` → 🐶 |
| `emd` | 飲食 | `emdba` → 🍌 |
| `emt` | 交通地點 | `emtck` → 🚀 |
| `emo` | 物品 | `emoig` → 💡 |
| `ems` | 符號 | `emfre` → ❤️ |
| `emv` | 活動 | `emvsb` → ⚽ |
| `emg` | 旗幟 | `emgtw` → 🇹🇼 |

不確定碼時可用萬用碼瀏覽：`emf*` 列出所有表情 emoji。

### 輸入功能
- 萬用碼 `*` 模糊查詢（prefix 預過濾加速）`v0.1.10` `v0.1.14`
- 補碼 `v`/`r`/`s`/`f` 快速選第 2–5 候選字（無法延伸編碼時）`v0.1.14` `v0.1.20`
- 滿碼自動送字（可選）`v0.1.10`
- `/` 穿透：空閒時直送 App（編輯器 slash command），打碼中仍走 CIN `v0.1.20`
- `'` 空閒時輸出頓號「、」（`';` 仍觸發注音反查）`v0.2.0`
- 中文標點：`[]` `[[` `]]` 走 CIN 查表（「」『』【】《》等）、`,` → ， `v0.1.18`
- Shift 快按切換中英、按住暫時英文 `v0.1.10`
- 全型空格：`,,` + Space 或 Shift+Space `v0.2.5`
- 中英模式切換 HUD 提示（「繁中」/「A」）`v0.1.14` `v0.2.0`
- 從其他輸入法切入時顯示當前模式 toast（可在偏好設定關閉）`v0.2.0`

### 查詢功能
- 同音字查詢：按 `'` 進入同音字模式，選字後列出所有同音字 `v0.1.13`
  - 先按 `'` 再打碼，送字後自動列出同音字 `v0.2.3`
- 注音反查：`';` 切換注音查碼模式（蝦米官方快捷鍵），輸入注音查嘸蝦米碼
  - 聲韻母可任意順序輸入，自動排列至正確 slot

### 智慧排序
- 字頻學習：unigram + bigram 前後文排序 `v0.1.10` `v0.1.13`
- 每 500 次自動 decay（×0.9）防膨脹 `v0.1.14`
- 同步資料夾：可指定 iCloud Drive 等雲端資料夾，跨機共享字頻與自訂擴充表 `v0.2.5` `v0.2.10`

### 設定介面
- GUI 偏好設定視窗（從輸入法選單開啟）`v0.1.15`
- 字體大小可調：游標模式 / 固定模式 / 模式提示 `v0.1.15`

## 需求

- macOS 14.0+（Apple Silicon）
- Xcode Command Line Tools（`xcode-select --install`）
- 嘸蝦米 CIN 字表（`liu.cin`）

## 安裝

打開「終端機」（應用程式 → 工具程式 → 終端機），貼上以下指令：

> 💡 首次使用會自動安裝 Xcode Command Line Tools（含 git），按照系統提示完成後再貼一次即可。

```bash
git clone https://github.com/FakeRocket543/yabomish.git && cd yabomish && ./setup.sh
```

安裝完成後：

1. **登出再登入**（蘋果選單  → 登出），或直接**重新開機**
2. 打開 **系統設定** → 左上角搜尋列貼上 `Yabomish` → 點選「輸入方式」→ 加入
3. 首次切換到 Yabomish 時，會自動引導你選擇 `liu.cin` 字表檔

> 💡 如果你的 `liu.cin` 放在專案根目錄（跟 `setup.sh` 同層），安裝時會自動匯入，不需要再手動選檔。

### 手動匯入字表

如果安裝時沒有自動匯入，或想更換字表：

1. 切換到 Yabomish 輸入法
2. 點選選單列的輸入法圖示 → **偏好設定⋯**
3. 點選 **匯入字表⋯** → 選擇你的 `liu.cin` 檔案

## 使用

### 基本操作

| 操作 | 按鍵 |
|------|------|
| 送字 | 空白鍵 |
| 選字 | 1–9, 0（或字表自訂 selKey） |
| 萬用碼 | `*` |
| 補碼選字 | `v`/`r`/`s`/`f`（第 2–5 候選） |
| 同音字 | `'`（送字後）或先按 `'` 再打碼 或 `,,TO` |
| 頓號 | `'`（空閒時） |
| 模式切換 | `,,` + 命令碼 + 空白鍵（如 `,,TS`） |
| 注音查碼 | `';` 切換 或 `,,ZH` |
| 全型空格 | `,,` + Space 或 Shift+Space |
| 刪碼 | Backspace |
| 清除 | Esc |
| 直送英文 | Enter |
| 直送 `/` | `/`（空閒時穿透給 App） |
| 中英切換 | 快按 Shift |
| 暫時英文 | 按住 Shift |
| 翻頁 | Tab / PageDown / PageUp |

### 中文標點

| 按鍵 | 輸出 |
|------|------|
| `'`（空閒時） | 、（頓號） |
| `,`（單按） | ， |
| `[` | CIN 查表（「、（、﹁、【⋯） |
| `[[` | CIN 查表（『、﹃、【、《⋯） |
| `]]` | CIN 查表（』、﹄、】、》⋯） |

### 同音字查詢

1. 方法一：送字後按 `'`，直接列出該字的所有同音字
2. 方法二：先按 `'` 進入同音字模式，輸入碼選字後列出同音字
3. ↑↓ 移動、←→ 翻頁、Enter 確認（固定模式：←→ 移動、↑↓ 翻頁）

### 注音反查

1. 輸入 `';` 進入注音查碼模式（顯示「注」提示）
2. 按注音鍵盤輸入注音符號（聲母、介音、韻母可任意順序，自動排列）
3. 按聲調鍵（3=ˇ 4=ˋ 6=ˊ 7=˙）或空白鍵（一聲）送出查詢
4. 選字窗顯示對應漢字及嘸蝦米碼，選字後直接送出到輸入框
5. 再按 `';` 或 Esc（空 buffer 時）回到一般模式

### 選字窗模式

**游標跟隨**（預設）— 選字窗出現在輸入游標旁。部分 App（Terminal、某些 Electron App）無法正確回報游標位置，會自動 fallback 到固定模式顯示（水平列）。

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
- 拆碼提示
- 注音反查
- 切入時顯示模式提示
- 蝦頭方向（← 向左 / → 向右）
- 狀態列名稱（Yabo / Yabomish）
- 匯入字表（選擇 `liu.cin` 檔案匯入）
- 同步資料夾（指定 iCloud Drive 等雲端資料夾，跨機共享字頻與自訂擴充表）
- Debug 模式（記錄操作日誌至 `~/Library/YabomishIM/debug.log`，方便回報問題）

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

# 切入時顯示模式提示
defaults write com.yabomishim.inputmethod.YabomishIM showActivateToast -bool true

# 蝦頭方向：left / right
defaults write com.yabomishim.inputmethod.YabomishIM iconDirection left

# 狀態列名稱：yabo / yabomish
defaults write com.yabomishim.inputmethod.YabomishIM menuBarLabel yabomish

# Debug 模式（記錄操作日誌）
defaults write com.yabomishim.inputmethod.YabomishIM debugMode -bool true

# 同步資料夾（指定後需重新登入，同步 freq.json + tables/*.txt）
defaults write com.yabomishim.inputmethod.YabomishIM syncFolder "$HOME/Library/Mobile Documents/com~apple~CloudDocs/YabomishIM"
```

## 更新

```bash
cd yabomish
git pull
./setup.sh
```

## 移除

```bash
cd yabomish
./uninstall.sh
```

腳本會移除 App、清除偏好設定，並詢問是否刪除使用者資料（`~/Library/YabomishIM/`）。完成後請登出再登入。

## 資料路徑

所有使用者資料存放在 `~/Library/YabomishIM/`：

| 檔案 | 說明 |
|------|------|
| `liu.cin` | 嘸蝦米字表（使用者提供） |
| `liu.cin.cache` | 二進位快取（自動產生，字表更新時自動重建） |
| `freq.json` | 字頻學習資料（自動產生，`,,RS` 可重置） |
| `zhuyin_data.json` | 注音對照表（內建於 App bundle，可自行覆蓋） |
| `t2s.json` | 繁→簡對照表（內建於 App bundle，可自行覆蓋） |
| `s2t.json` | 簡→繁對照表（內建於 App bundle，可自行覆蓋） |
| `debug.log` | Debug 日誌（開啟 Debug 模式後自動產生） |
| `tables/emoji.txt` | emoji 擴充表（安裝時自動部署，1,906 個 emoji） |
| `tables/*.txt` | 自訂擴充表（tab-separated `編碼<Tab>內容`，`,,RL` 重載） |

App 載入順序：先找 `~/Library/YabomishIM/` 下的檔案，找不到才用 App bundle 內建版本。擴充表從 `tables/` 目錄載入；如有設定同步資料夾，該路徑下的 `freq.json` 與 `tables/*.txt` 也會一併載入，適合將自訂擴充表（如 `prompts.txt`）放在 iCloud Drive 跨機共享。更換字表只需替換 `~/Library/YabomishIM/liu.cin`，無需重新編譯。

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
│   ├── DebugLog.swift                 # Debug 日誌（~/Library/YabomishIM/debug.log）
│   ├── Prefs.swift                    # UserDefaults 偏好設定
│   └── PrefsWindow.swift              # GUI 偏好設定視窗
├── Resources/
│   ├── Info.plist
│   ├── zhuyin_data.json
│   ├── t2s.json / s2t.json
│   ├── icon.icns / icon.tiff / icon_left.tiff / icon_right.tiff
│   └── YabomishIM.entitlements
├── build.sh                           # 編譯腳本
└── install.sh                         # 安裝腳本（互動選擇蝦頭方向、狀態列名稱）
```

## 版本歷程

| 版本 | 日期 | 重點 |
|------|------|------|
| 0.2.14 | 2026-03-24 | 同音字打碼後空白鍵送字失效修正 |
| 0.2.13 | 2026-03-24 | 拼音查碼模式（`,,PYS` 簡體 / `,,PYT` 繁體）、游標跟隨左邊界溢出修正 |
| 0.2.12 | 2026-03-23 | 游標跟隨 hasCursor 判斷改善、install.sh defaults read 修正 |
| 0.2.11 | 2026-03-17 | 修正滿碼送字 bug、擴充表支援空格分隔、程式碼命名修正 |
| 0.2.10 | 2026-03-17 | 擴充表系統（`tables/*.txt`）、emoji 1906 碼、動態碼長、候選字點擊送字、`,,RL` 重載 |
| 0.2.8 | 2026-03-17 | 注音鍵位對應修正（ㄛ/ㄨ/ㄟ/ㄩ/ㄝ） |
| 0.2.7 | 2026-03-16 | `,,ZH` 注音查碼、`,,TO` 同音字查詢命令 |
| 0.2.6 | 2026-03-15 | 全型空格、字頻 iCloud 同步、偏好設定分組、視窗前景化修正 |
| 0.2.4 | 2026-03-15 | 注音選字送出、debug 模式、匯入修正（osascript）、LSUIElement |
| 0.2.3 | 2026-03-14 | 同音字修正：聲調區分、panel 閃消失、先按 `'` 模式、移除 mid-compose `'` |
| 0.2.1 | 2026-03-14 | 字表匯入引導、DMG 打包、切入 toast 修正、移除僅圖示選項、安裝流程改善 |
| 0.2.0 | 2026-03-14 | `,,` 命令系統（8 種輸入模式）、頓號 `'`、繁簡轉換、日文假名、多螢幕修正、狀態列名稱選項 |
| 0.1.20 | 2026-03-13 | `/` 穿透模式、同音字尾綴 `'`、補碼 VRSF、注音 `';` 觸發、ㄣ/ㄥ 修正 |
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

## Roadmap

- **0.3.x** — DMG 打包安裝 + Homebrew Cask 支援

## 致謝

- [@Marsjelly](https://github.com/Marsjelly) — 英文模式 Shift 修正、游標跟隨定位改善、安裝權限修正
- [@jackyhuang72](https://github.com/jackyhuang72) — 注音鍵位對應修正（ㄛ/ㄨ/ㄟ/ㄩ/ㄝ）
- [@haoweicrushu](https://github.com/haoweicrushu) — 提議碼長可設定（PR #2，已改為動態計算）
- [威注音輸入法 vChewing](https://github.com/vChewing/vChewing-macOS) — 游標跟隨模式邊界處理參考、注音字表資料來源（[VanguardLexicon](https://atomgit.com/vChewing/vChewing-VanguardLexicon)，MIT 授權）

## 支持作者

覺得好用？來吃一球 gelato 🍨
[Golden Rooster](https://shop.goldenrooster.tw)

## 資料來源

### 注音對照表

內建 `zhuyin_data.json` 取自[威注音輸入法](https://github.com/vChewing/vChewing-macOS)的 [VanguardLexicon](https://atomgit.com/vChewing/vChewing-VanguardLexicon) 字表（MIT 授權），涵蓋 7,633 字、1,387 組注音。字表已按威注音的繁體單字權重排序，罕見讀音（權重為 0）不收錄，確保同音字查詢結果貼近實際使用。

### 繁簡對照表

`s2t.json`、`t2s.json` 衍生自 [OpenCC](https://github.com/BYVoid/OpenCC) 的 `STCharacters.txt` 及 `TSCharacters.txt`，轉換為 JSON 格式並取用部分子集。原始資料以 Apache License 2.0 授權。

> Copyright OpenCC Authors. Licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

曾使用 [g0v/moedict-data](https://github.com/g0v/moedict-data)（教育部《重編國語辭典修訂本》）作為注音資料來源，但萌典收錄所有讀音不分常用罕用，導致同音字查詢混入大量罕見讀音的字（如「色」的 ㄕㄜˋ、「庫」的 ㄕㄜˋ），改用威注音字表後解決。

## 授權

MIT
