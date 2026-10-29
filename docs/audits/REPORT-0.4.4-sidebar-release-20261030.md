# 0.4.4 發佈報告 — 側邊欄按鈕移除＋截圖更新

日期：2026-10-30｜run：ralph 自主流程｜最終 commit：`2c8a693`

## 目標

1. 移除設定程式右上角 NavigationSplitView 側邊欄開關按鈕（macOS 26 下 `.toolbar(removing: .sidebarToggle)` 失效）。
2. README 截圖更新為 12 頁新介面、誌謝加入貢獻者。
3. 關閉 GH issues #17、#18（功能已在 0.4.0 實作）。
4. 撤掉 v0.4.3 release，發 v0.4.4（DMG 簽章＋公證）。

## 變更

| 項目 | 內容 |
|---|---|
| `ContentView.swift` | `NavigationSplitView(columnVisibility: .constant(.all))` 常數綁定——NSV 不產生收起 affordance，側邊欄恆顯示；保留 `.toolbar(removing:)` 作雙保險 |
| 版號 | IM／Prefs Info.plist → 0.4.4 |
| CHANGELOG | 新增 [0.4.4] 段 |
| README | 設定程式截圖重截（8 頁：輸入/聯想/一般詞庫/專業詞庫/快捷碼/候選窗/介面/關於）、圖表重排、引導頁數 3→4、誌謝新增 plateaukao、jackyhuang72 |
| docs/images + images/ | 8 張 webp（920×632，cwebp q82） |
| tag | v0.4.3 刪除（兩 remote）、v0.4.4 指向 `2c8a693` |

## 驗證

- `swiftc` 全量編譯通過（universal x86_64+arm64）
- 本機安裝 + `open /Applications/YabomishPrefs.app` 截圖：titlebar 無開關鈕、側邊欄可見（無「Daemons」對話框）
- **E2E**：掛 `Yabomish-0.4.4-full.dmg` → 跑 installer → `/Library/Input Methods/` 為 0.4.4、`corpusVariant=full`、重新截圖確認按鈕消失
- DMG：兩個都 `codesign --verify` 通過、`notarytool` Accepted、`stapler staple` + `validate` 成功
- GH Release `v0.4.4` 建立（lite + full 資產）；GH Pages workflow 由 `site/**` push 觸發、run success

## 限制

- `Yabomish-0.4.3-*.dmg` 本機檔案已刪除對應 Release，repo 目錄殘留本機副本（不再上傳）。
- pkg 不產出（無 Developer ID Installer 憑證）；DMG 為唯一散佈物，與前版一致。
- 截圖以 `screencapture -R` 矩形擷取，`--args -page N` 掛鉤已存在於 `main.swift`（測試用）。

## 後續建議

- 更新需「移除重加輸入法」才刷新 TIS 註冊名（Yabo）——手冊已寫，Release 說明也帶。
- `tools/release.sh` 公證段已支援 `NOTARY_PROFILE`（keychain `yabomish-notary`）；未來 CI 可掛 `APPLE_ID`+app 密碼做自動化。
