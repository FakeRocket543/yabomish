# Yabomish

macOS 嘸蝦米輸入法的開源實作，純 Swift，無需 Xcode。

> 本專案不包含嘸蝦米字表，需使用者自行取得 `liu.cin`。

## 需求

- macOS 14.0+（Apple Silicon）
- Xcode Command Line Tools（`xcode-select --install`）
- 嘸蝦米 CIN 字表（`liu.cin`）

## 安裝

```bash
# 將 liu.cin 放到專案根目錄，然後：
./setup.sh
```

到 **系統設定 → 鍵盤 → 輸入方式** 加入「Yabomish」。

## 使用

| 操作 | 按鍵 |
|------|------|
| 送字 | 空白鍵 |
| 選字 | 1-9 |
| 萬用碼 | `*` |
| 刪碼 | Backspace |
| 清除 | Esc |
| 直送英文 | Enter |
| 中英切換 | 快按 Shift |
| 暫時英文 | 按住 Shift |
| 翻頁 | Tab / PageDown / PageUp |

## 字表路徑

App 依序尋找：
1. `~/Library/YabomishIM/liu.cin`（優先）
2. App bundle 內建 `Resources/liu.cin`（fallback）

更換字表只需替換 `~/Library/YabomishIM/liu.cin`，無需重新編譯。

## 授權

MIT
