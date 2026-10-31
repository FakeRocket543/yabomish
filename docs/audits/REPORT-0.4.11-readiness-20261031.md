# 0.4.11 出貨準備報告（2026-10-31）

## 目標

0.4.10（`936d3b7`）後落的兩輪 review 修復（`166d7bc`、`dc01818`）收尾：
自審同類殘留問題 → 修補 → 驗證 → 文件同步 → 定版，推進到「可進 SOP 打包」狀態。

## 摘要

- 自審發現 **3 個殘留問題**（P2×2、P3×1），全部修完。
- 測試套件從**編譯失敗**修回 **138/138 通過**。
- `min`／`full`／Prefs 三目標在 `10d5a56`（含全部修正）編譯 0 錯誤。
- 手冊補上 `,,AI`／preset／AI 分頁完整覆蓋（advisory 指出的缺口）；順帶修正 FAQ 的 syncFolder 過期敘述。
- `release: 0.4.11`（`7e44b62`）已推 origin＋github；**未跑 DMG/公證/Release**——等使用者拍板後照 SOP §2–§6 走。

## 變更（本輪新增，commits 10d5a56 / 804af05 / 7e44b62）

| 檔案 | 修正 | 嚴重度 |
|------|------|--------|
| `InputEngine.swift` | 恢復 `isSameSoundMode` 唯讀 accessor——`504e3f5`（0.4.5，`isInSpecialMode` 擴 `_isLLMPromptMode` 時誤刪）移除後測試 `main.swift:686` 編譯失敗 | P2 |
| `yabomish.sh:233` | `.prev` 保留提示查舊位置（`INSTALL_DIR`），永不顯示→改查 `USER_DIR` | P3 |
| `yabomish.sh:353` | `do_uninstall` 不清 `USER_DIR` 內 `.prev`/`.rollback-tmp` 備份（不 wipe 資料也殘留）→ 無條件移除 | P2 |
| `site/ch07` | 「四種型別」→五種（+`preset`），JSON 範例＋型別表＋`preset`／`,,AI` 專節 | docs |
| `site/ch08` | 新增 8.11 AI（mode/cli/http/preset 編輯器），說明→8.12、關於→8.13 | docs |
| `site/ch10` | FAQ「同步資料夾 UI 已移除」過期→改寫為關於頁 NSOpenPanel 現況 | docs |

## 自審結論（同類殘留掃描結果）

已核對、無殘留：
1. **Protocol 見證**——`engineDidRequestLLM(_:)` 簽名與 protocol 一致，engine `,,AI<prompt>` inline 分支（`InputEngine.swift:607`）走見證實作；其餘 delegate 方法無預設參數版。
2. **`{clip}` 唯一入口**——`runAIHTTP` 不附加；`embeddedClip` 快照在 preset→`engineDidOpenLLMPrompt`→`requestLLM` 全鏈一致；CLI 模板 `{clip}` 與 prompt 內嵌共用同一快照。
3. **`llmGeneration`**——static 全 app 共享，`requestLLM`/`deactivateServer` 皆 bump；stale→剪貼簿＋toast（非丟棄）；失敗訊息 stale 也送。
4. **PresetPickerPanel**——`pick()` 有 `items.indices.contains` 邊界檢查，0→第 10 列安全；Esc/失焦 dismiss。
5. **Toast 去重**——engine 端 `InputEngine.swift:605` 註解明確不發，controller `requestLLM:1286` 單一「生成中」。
6. **`.prev` 路徑**——install/rollback/uninstall 三路全數遷移或相容（rollback 新舊位置都認）；無殘留 `INSTALL_DIR/*.app.prev` 寫入點。
7. **`,,PR〈未知碼〉`**——toast＋自動開選單 fallback（`InputEngine.swift:593-597`）在。

## 驗證證據

| 檢查 | 結果 |
|------|------|
| `./yabomish.sh test` | **138 passed, 0 failed**（修正前：編譯失敗 `isSameSoundMode` no member） |
| `./yabomish.sh build min` | OK（2.1M，build `10d5a56`-era，0 錯誤） |
| `./yabomish.sh build full` | OK（109M，0 錯誤） |
| `bash -n yabomish.sh` / `tools/release.sh` | 語法通過 |
| `cd site && npm run build` | 13 頁全 build，0 警告 |
| prefs↔UI 對齊（.audit/prefs-matrix.md） | 52 key 全覆蓋，0 ❌，min/full 對齊 |

## 限制

- **未驗證執行期 `,,AI`**：`fm` 需 macOS 27+ Apple Intelligence；本輪為靜態審查＋編譯＋單元測試，無端到端 LLM 呼叫證據（無 `fm` 環境）。
- **未驗證 TIS 幻影修復實效**：`.prev` 移出 Input Methods 的修正依 commit 敘述＋腳本路徑審查成立，但未在本機做「安裝兩次→看 menubar 是否單一 β」實驗。
- 手冊 8.11 新增的 anchor 連結用目錄頁級連結（站內慣例不帶 `#heading` anchor）。

## 後續（SOP §2–§6，prod deploy，等指令）

1. 語料 zip（lite/full）→ `make_corpus_manifest.py --tag v0.4.11` → commit manifest（**必先於打包**）
2. `./tools/release.sh lite` + `full` → `Yabomish-0.4.11-{lite,full}.dmg`
3. notarytool submit×2 → staple → `spctl --assess` 驗收
4. tag `v0.4.11`、push 兩 remote、`gh release create`（四資產：兩 DMG＋兩語料 zip）
5. 驗 lite zip URL 200、Pages 手冊部署
