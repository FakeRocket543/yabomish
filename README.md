# Yabomish

macOS 嘸蝦米輸入法的開源實作，純 Swift。

> 本專案不包含嘸蝦米字表，需使用者自行取得 `liu.cin`。

## 特色

- 純 Swift，無第三方依賴
- 硬體 keyCode 對應，不受鍵盤佈局影響（Dvorak、Colemak 等皆可）
- 自訂選字窗（NSVisualEffectView 毛玻璃風格）
- 字頻學習：依使用頻率 + 前後文 bigram 自動調整候選字排序
- 同音字查詢：選字後按 `'` 查同音字
- 萬用碼 `*` 模糊查詢
- 滿碼自動送字（可選）

## 需求

- macOS 14.0+（Apple Silicon）
- Xcode Command Line Tools（`xcode-select --install`）
- 嘸蝦米 CIN 字表（`liu.cin`）

## 安裝

打開「終端機」（應用程式 → 工具程式 → 終端機），依序貼上：

```bash
# 1. 下載專案
git clone https://github.com/FakeRocket543/yabomish.git
cd yabomish

# 2. 將你的 liu.cin 複製到這個資料夾
cp /你的liu.cin路徑/liu.cin .

# 3. 一鍵安裝（會自動安裝編譯工具、編譯、安裝）
./setup.sh
```

安裝完成後，到 **系統設定 → 鍵盤 → 輸入方式 → 點左下角「+」** 加入「Yabomish」。

## 使用

| 操作 | 按鍵 |
|------|------|
| 送字 | 空白鍵 |
| 選字 | 1-9, 0 |
| 萬用碼 | `*` |
| 補碼選第一字 | `v` |
| 刪碼 | Backspace |
| 清除 | Esc |
| 直送英文 | Enter |
| 中英切換 | 快按 Shift |
| 暫時英文 | 按住 Shift |
| 翻頁 | Tab / PageDown / PageUp |
| 同音字查詢 | `'`（先打字送出，再按 `'`） |
| 同音字翻頁 | ← → |
| 同音字選字 | ↑ ↓ 移動，Enter 確認 |

### 同音字查詢

1. 正常輸入送出一個字（例如送出「是」）
2. 按 `'` 進入同音字模式
3. 輸入嘸蝦米碼，選字窗會列出該字的所有同音字
4. 用 ↑↓ 移動、←→ 翻頁、Enter 確認

## 設定

```bash
# 選字窗固定在螢幕底部中央（不受 App 影響）
defaults write com.example.inputmethod.YabomishIM panelPosition fixed

# 選字窗跟隨游標（預設）
defaults write com.example.inputmethod.YabomishIM panelPosition cursor

# 輸入滿碼唯一候選字時自動送出（不用按空白鍵）
defaults write com.example.inputmethod.YabomishIM autoCommit -bool true
```

> 部分 App（Terminal、某些 Electron App）無法正確回報游標位置，選字窗會自動 fallback 到上次有效位置或螢幕底部。遇到此情況也可切換為 `fixed` 模式。

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
| `zhuyin_data.json` | 注音對照表，供同音字查詢（內建於 App bundle，也可自行覆蓋） |
| `freq.json` | 字頻學習資料（自動產生） |

App 載入順序：先找 `~/Library/YabomishIM/` 下的檔案，找不到才用 App bundle 內建版本。

更換字表只需替換 `~/Library/YabomishIM/liu.cin`，無需重新編譯。

## 支持作者

覺得好用？來吃一球 gelato 🍨
[Golden Rooster](https://shop.goldenrooster.tw)

## 授權

MIT

## 更新紀錄

### v0.1.14
- 修正：非數字 selKey（如 `asdfghjkl;`）不再造成 crash
- 修正：移除矛盾的 sandbox entitlements
- 修正：cursor mode 多螢幕邊界檢查改用正確螢幕
- 新增：中英模式切換時顯示 HUD 提示（「中」/「A」）
- 改善：字頻每 500 次自動 decay，防止 freq.json 無限膨脹
- 改善：萬用碼查詢用 prefix 預過濾，減少全表掃描
