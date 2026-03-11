# Yabomish

macOS 嘸蝦米輸入法的開源實作，純 Swift。

> 本專案不包含嘸蝦米字表，需使用者自行取得 `liu.cin`。

## 需求

- macOS 14.0+（Apple Silicon）
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
| 選字 | 0-9 |
| 萬用碼 | `*` |
| 刪碼 | Backspace |
| 清除 | Esc |
| 直送英文 | Enter |
| 中英切換 | 快按 Shift |
| 暫時英文 | 按住 Shift |
| 翻頁 | Tab / PageDown / PageUp |

## 更新

```bash
cd yabomish
git pull
./setup.sh
```

## 字表路徑

App 依序尋找：
1. `~/Library/YabomishIM/liu.cin`（優先）
2. App bundle 內建（fallback）

更換字表只需替換 `~/Library/YabomishIM/liu.cin`，無需重新編譯。

## 授權

MIT
