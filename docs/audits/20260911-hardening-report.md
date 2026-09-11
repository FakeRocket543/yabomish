# Yabomish 管理程式強化報告 — 2026-09-11（第二輪）

對象：`yabomish.sh`（互動選單＋建置/安裝/移除）、`tools/release.sh`（DMG/pkg 發佈管線）、`tools/all_platforms.sh`（self-CI）。

## 決策：Intel 相容

**要顧，分層做。** macOS 14 仍支援 Intel（2018–2020 機種），輸入法是裝機工具：
- `yabomish.sh`：`ARCH=$(uname -m)`，Intel 機器自己編 x86_64 — 零額外成本
- `tools/release.sh`：DMG 發給別人 → universal binary（`swiftc_universal` helper：雙 target 各編一次＋`lipo -create`＋`lipo -info` 驗證）。`YABOMISH_ARCH=arm64|x86_64` 可只編單架構省時間。codesign 對所有 slice 簽署，流程不變
- `YabomishIM/Tests/run_tests.sh`：`-target arm64-…` → `$(uname -m)`（Intel 機器連測試都跑不了的死角）
- ⚠️ x86_64 slice 在本機（arm64）只能編譯不能執行 — Intel 實機或 notarization log 需另行驗證

## yabomish.sh（249 → 395 行）

### 新 CLI（非互動，取代 `printf '2\n1\n' |` 餵選單的 hack）

```
./yabomish.sh                      → 互動選單（不變）
./yabomish.sh build [full|lite|min]
./yabomish.sh install
./yabomish.sh uninstall [--yes]
./yabomish.sh test
```

壞參數 → usage 到 stderr、exit 2。`all_platforms.sh` 的 `macos_build` 已改用 `bash yabomish.sh build full`。

### 健壯性修復（15 項全做）

| 項 | 內容 |
|----|------|
| fetch_corpus 逐檔檢查 | `corpus_ready()` 對照各等級標記檔（lite+ 8 bins＋region 兩檔；full 加 terms_*.bin），不再「有任一 .bin 就跳下載」 |
| fetch_corpus staging | unzip 到 `build/corpus_staging/` 再只搬 `*.bin`/`region_*.txt` 進 Resources — 壞 zip 不能覆寫 Info.plist/manifest（與 DataDownloader 同款） |
| 原子安裝 | `cp → .new` → `mv 舊版 → .old` → `mv .new 進位` → 清 `.old`；install_im/install_prefs 同套。失敗不再留「沒有輸入法」空窗 |
| VER 守衛 | CHANGELOG 解析失敗在 `rm -rf` 前就 `err`，不再先刪舊 build 才爆 |
| 選單韌性 | `read … || break`/`|| m=""`/`|| c=""` 處理 EOF；`menu_run` 子殼層包住動作，`err` 的 exit 1 只回報不關選單；`&&` 串接保證建置失敗不會裝半套 |
| 架構 | `arm64` 硬編碼 → `"$ARCH-apple-macos14.0"` |
| 測試入口 | 選單加 `T) 執行測試` |
| 移除完整性 | 加刪 `~/Library/Input Methods/YabomishIM.app`（all_platforms 裝的使用者層級副本）＋`killall YabomishPrefs` |
| 本地簽名 | install_im 後 `codesign -s - --force --deep`（與 all_platforms.sh 一致） |
| check_xcode 範圍 | 只在 build/選單路徑需要；CLI 的 install/uninstall/test 不再要求 CLT |
| curl 續傳 | `-C -`＋失敗時清掉重試一次（防 416 迴圈） |
| sudo -v | install_im/install_prefs 開頭預取時間戳，不再連問三次密碼 |
| shellcheck | SC2046（find word splitting → while-read array）、SC2010（ls\|grep → glob 計數）清零 |
| drift 註解 | build_im 頂部加一行指向 release.sh 為 release 路徑對應 |

## tools/release.sh

- `swiftc_universal()` helper（:31-57）：雙 arch 編譯＋lipo＋exec bit＋`lipo -info` 印出
- build_im/build_prefs 改用 helper；`-DMINIMAL`、framework flags、source list 原樣保留
- DMG README 字串「Apple Silicon」→「Apple Silicon 與 Intel」
- 上一輪的 postinstall chown/SCRIPT_DIR、ASC key mktemp、installer 單引號守衛仍在

## tools/all_platforms.sh

- `macos_build` 改用 CLI 契約 `bash yabomish.sh build full`
- `macos_test` 維持直接跑 run_tests.sh（CLI `test` 只是 exec 同一腳本，多一層無益）
- 上一輪的 pipefail＋out-capture 全保留

## 驗證

- `bash -n` 三腳本全過；`shellcheck -S warning` **全零**（含 release.sh 我補的 SC2046）
- `bash yabomish.sh`（無參數）→ 選單正常、EOF 乾淨退出；`bogus` → usage＋exit 2
- `bash yabomish.sh test` → 138 passed, 0 failed
- `bash yabomish.sh build full` → YabomishIM.app 110M＋Prefs 成功（29s）
- `bash yabomish.sh build min` → 3.1M 極簡版成功（20s）
- HardenMain 的 harness 實測：corpus_ready 真值表、hostile zip 不覆寫 Info.plist/manifest、hash 不符不裝、curl 失敗無殘留、選單失敗回圈不關閉
- HardenRelease 的 harness：`swiftc_universal` 產出 `Mach-O universal binary with 2 architectures`＋exec bit；`YABOMISH_ARCH=arm64` 產 thin binary

## 未做（刻意）

- 增量編譯（`-incremental`＋保留中間產物）：swiftc 的 incremental 對多檔案模組效益有限且會讓 build 目錄狀態複雜化；29s 全量編譯對此規模可接受
- `uninstall --yes` 會連使用者資料一起刪（contract 明定）；無 `--yes` 且非 tty 時安全取消
