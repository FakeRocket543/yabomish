# 手冊與 README 全面修訂 — 審計與修復報告（2026-09-10）

> 方法：雙子代理平行審計（手冊 12 章逐章 vs 程式碼現況；README 全文 vs 現況）
> ＋本機結構 E2E（建置／內鏈／圖檔／frontmatter）＋ ralph 迴圈修復至舊錯誤字串清零。
> 事實基準：CHANGELOG [Unreleased]～v0.3.60、YabomishIM/YabomishPrefs 原始碼、
> yabomish.sh／tools/release.sh、yabomish_ios master @ 332e74e。

## 1. 審計發現總量

| 來源 | P1（照做會失敗／功能已不存在） | P2（缺漏） | P3（精確度） |
|------|------|------|------|
| 手冊逐章 | 11 | 7 | 6 |
| README | 2 | 5 | 3 |

## 2. P1 修復（全部完成）

1. **ch12 整章改寫**：12.3 跨裝置同步（S3/Keychain/同步頁）、12.4 Hermes 詢問——iOS 端已於 2026-08 移除，改寫為「目前沒有跨裝置同步」＋手動搬移說明；12.2 完整存取開關說明與現況相反（bisect 遺留 `RequestsOpenAccess=true`），改為誠實標註；12.5 對照表整表翻新
2. **ch01 安裝腳本選項號**：更新用 `4)`（實為 `1)`，`4)` 只重裝設定程式）、移除 `6)`（實為 `5)`）、「不會刪使用者資料」（腳本會詢問並刪除）
3. **ch01 安裝過程**：已不詢問蝦頭方向／狀態列名稱（自動套用既有偏好）
4. **舊路徑 `~/Library/YabomishIM/`**：ch01／ch07（擴充表、快捷碼）→ `~/Library/Application Support/Yabomish/`
5. **ch08「注音反查」偏好列刪除**：開關已於 0.3.62 移除（`,,ZH` 無需開關）
6. **ch10**：用詞習慣分頁位置、freq.db／debug.log 路徑、同步資料夾 UI、移除選項號
7. **ch09 `user_phrases.txt`**：UserPhrases 已於 0.3.62 刪除，移除（README 同）
8. **ch04 日文模式 toast**「仮」→「日」
9. **ch05 用詞習慣位置**「輸入」→「聯想與詞庫」
10. **ch03 翻頁表**：`Shift+Tab` 上一頁不存在（一律下一頁）；方向鍵行為分垂直／水平兩欄，消除與 3.1 的自相矛盾
11. **Emoji 聯想非擴充表**：ch01／ch05／ch07 改為 `emoji_char_map.json` 語料檔驅動

## 3. P2 修復（全部完成）

- **ch04 工具命令表擴充**：`,,LH`／`,,RH`、`,,SG`、`,,V/VT/VS`（含 0.55 秒剪貼簿還原）、`,,X` 語境系列；`,,RL` 補「一併重載自訂指令與 snippets」；Esc 一鍵退出特殊模式
- **ch08**：8.1 補查字歷史 GUI（檢視／CSV／清除）；層序改「三層文字＋第四張 Emoji 卡」；8.4 補介面外觀三態＋切換顯示；蝦頭補授權換圖行為；8.5 補版本號
- **ch02／ch05**：補純聯想顯示的 Enter／空白鍵不代選行為、預先反白預設關說明
- **ch12 補 iOS 新功能**：查字歷史、字級聯想、Shift＋數字（實體鍵盤）、行為對齊清單
- **ch07 7.3**：iCloud 同步節改寫（UI 已移除、`syncFolder` 為進階 defaults write）
- **ch01**：補極簡安裝模式（僅原始碼可選）＋ DMG 2.8MB 大小＋ commands.json 部署
- **README 安裝段改寫**：方式一 DMG 兩包制（表格＋流程＋語料下載說明）、原始碼降為方式二、tagline「離線聯想」加但書；設定程式五分頁清單補全部新卡
- **28 vs 36 口徑回修**：程式碼事實為 **28 專業詞典**（DomainData）＋12 一般詞庫；CHANGELOG／release.sh／手冊安裝章的「36 部專業詞典」全數改為 28（36 是 terms_*.bin 檔數，其中 8 個實為一般詞庫）
- **index.astro** 章節描述：ch01（編譯安裝→DMG／原始碼）、ch05（三層→層序＋Emoji 卡）、ch12（移除「跨裝置同步、Hermes 詢問」）

## 4. P3 修復

- 自動送字條件（ch02/ch08）：「打滿 4 碼」→「唯一候選且碼無法再延伸（≥2 碼）」
- ch05 虛詞清單照 `skipChars` 重寫（原列「耶囉嘛哩咧」不在程式中）
- ch05 專業詞典示例對齊 DomainData（紡織食品→輕工業等）
- ch09：freq.db 補 `lookup_history` 表、檔案樹補下載語料、「13 類」→12
- 名詞對齊 UI：模糊匹配→鄰鍵容錯、同音字多音→同音多讀、中國流行語→中式流行語
- ch06：拆碼提示顯示位置統一（獨立提示窗）、補查字歷史段、Esc 退出加註
- README：架構註解「6 一般」→12、`,,V` 系列補剪貼簿還原、Enter 快參加註、Emoji 補可調

## 5. 結構 E2E（修復後）

```
astro build：13 頁建置成功（771ms）
frontmatter order：1–12 完整無重複
內部連結：0 死鏈；圖檔引用 8/8 存在
舊錯誤字串 grep 清零：Library/YabomishIM（正向匹配）0、user_phrases 0、
仮 0、「6) 移除」0、「36 部」0
release.sh：字串修改後 bash -n 通過
```

## 6. 變更檔案

```
site/src/content/chapters/01,02,03,04,05,06,07,08,09,10,11,12-*.md（12 章全動）
site/src/pages/index.astro
README.md
CHANGELOG.md（36→28 口徑）
tools/release.sh（36→28 口徑）
```

## 7. 未動與備註

- README 架構清單缺漏檔（P3）：清單本質是導覽用途，補 17 個檔案意義有限，維持現況（審計建議存參）。
- ch08 設定項表格的截圖（prefs-input.webp 等）為舊版 UI 畫面，新一波卡片（預先反白／Shift＋數字／Emoji 卡）未入圖——下次 UI 截圖更新時一併重拍。
- ch11 萌典詞組筆數欄格式不一（選配），未動。
