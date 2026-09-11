# Yabomish 全專案審查 — 2026-09-11

範圍：YabomishIM（11 檔 + Shared 15 檔）、YabomishPrefs（19 檔）、tools/（shell + 26 支 Python）、yabomish.sh、.github/workflows。不含 test_0414/、data/、yabomish_data/、doc*/、site/。

驗證基線：IM 與 Prefs 兩 target `swiftc -typecheck` 皆通過；`Tests/run_tests.sh` 138 passed / 0 failed；shellcheck 僅 3 個低風險警告。

統計：🔴 2 · 🟠 12 · 🟡 14 · 🟢 16（#29–44）；另 tools/*.py 語料管線獨立計：🟠 2 · 🟡 7 · 🟢 4

---

## 🔴 Blocker

### 1. Quick Action 把選取文字插進 osascript — shell/AppleScript 注入
`tools/install_quick_action.py:35,39`

產生的 workflow 內嵌 Python 用 `os.system(f'osascript -e \'display notification "已加入: {text}" ...\'')`，`text` 是使用者在任何 app 選取的文字。選取內容含 `"` 可跳出 AppleScript 字串（→ `do shell script` 任意執行），含 `` ` ``/`$()` 則在 /bin/sh 層執行。輸入法相關工具處理任意選取文字，這是實際可觸發的 RCE。

修法：`subprocess.run(["osascript","-e",script])` 不走 shell，文字用 `on run argv` 傳入；或通知不帶原文。

### 2. Pin 模式按 Enter 把 `PIN:xxx` 字面文字 commit 進文件並污染 freq.db
`YabomishIM/Sources/Shared/InputEngine.swift:319-328`

`handleEnter` 無 pin-mode 分支。pin 模式下 `_composing` 是 UI 標籤 `"PIN:"+_pinCode`（:148），controller 在 composing 非空時把 Return 路由到 `handleEnter`（YabomishInputController.swift:509-520）→ `_commitText("PIN:abc")` 把字面字串插入文件，且 :846-851 的 `freqTracker.record(code:"PIN:abc", …)` + bigram/trigram + `saveIfNeeded()` 把垃圾 key 寫進 freq.db；`_isPinMode`/`_pinCode` 未清，pin 模式殘留。

修法：`handleEnter` 比照 `handleEscape`(:333) 先解除 pin 模式。

---

## 🟠 Critical

### 3. autoCommit 的 `_eatNextSpace` 造成幻影空白＋吞掉下一組字的空白
`InputEngine.swift:218,226-228`；路由 `YabomishInputController.swift:479-488`

autoCommit 觸發時 `_commitFirstCandidate(); _eatNextSpace = true`，但 `_composing` 已空 → controller :479 `engine.composing.isEmpty → return false`，空白直接進文件（幻影空白）。即使送到 engine，`handleSpace` :227 先測 `_composing.isEmpty` return，flag 永遠不會被消費。`_eatNextSpace` 只在 `_resetComposing`(:931) 清除，而 `handleLetter` 不清它 → 殘留 flag 在下一組字的第一個空白被吞掉（:228 return，不 commit 首候選）。每次 autoCommit+space 淨效果：多一個幻影空白＋下一次組字丟一個空白。

修法：autoCommit 分支不要設 flag（space 根本到不了 engine），或在 `_commitFirstCandidate`/`handleLetter` 清除。

### 4. `open` 型指令把 app 名插進單引號 shell — 同步來源 commands.json 的隱形 RCE
`CommaCommandRunner.swift:59-62` → `_runShellAsync`(:139-150) 走 `/bin/zsh -c`

`open -a '\(app)'`：`app` 含 `'` 即逃出引號執行任意指令。commands.json 在 yabomish-sync.sh 同步清單內，且程式碼自己已把 hermes 限 loopback（:113-116 註解明說「tampered entry could exfiltrate」）——同一份可被竄改的檔案，`shell`/`open` 型卻無任何把關；文件還把 `open` 描述成只是「開啟 app」。對照內建 `,,P`（InputEngine.swift:641-647）用 Process+argv 無 shell。

修法：`open` 改用 `Process` argv（`/usr/bin/open -a app`）；sync pull 時對新增/變更的 shell/open 項目要求使用者確認。

### 5. `,,XS` 永遠把 profile inputMode 覆寫成 "t"
`ContextProfileCommands.swift:23-25`；`ContextProfile.swift:71-91`

`snapshotCurrent()` 從 UserDefaults 抓 9 個欄位但沒有 inputMode（engine 的 `_inputMode` 是 session-only，不落盤）→ `profile.inputMode = snap.inputMode` 永遠寫入預設 `"t"`。使用者在編輯器選的「簡中」模式在 `,,XS` 後被洗掉，下次 `,,X<code>` 強制回繁體。

修法：刪掉該行（保留已存值），或把 engine 目前 mode 傳進 snapshotCurrent。

### 6. CINM 編譯器 UInt16 offset 截斷 — 大 .cin 表靜默回傳錯字
`CINCompiler.swift:99-108`；讀端 `CINTable.swift:261-280`

chars section 超過 65,536 scalar slots 時 val offset 被 clamp 成 UInt16.max（單碼 >255 值也被截）。`readChars` 的 `lastOff <= d.count` 檢查照過（檔案本來就更大）→ 第 65,535 slot 之後每個 entry 回傳別碼的字，使用者 commit 錯字且無任何錯誤。觸發：值總量 >65k scalar 的 .cin（約 3 萬條多字詞表即可）。

修法：valIdx 改 u32 offset/u16 count，或 import 時明確報錯拒絕。

### 7. liu.bin 非原子寫入 — 重編譯時 truncate 活著的 mmap → SIGBUS
`CINCompiler.swift:129` `try buf.write(to:)` 原地 truncate

`CINTable.reload()` 刻意在 stateLock 外跑 `ensureFreshCompiledBin()` 讓查表不中斷（CINTable.swift:87-102），但查表與 activateServer 的 preheat 執行緒（YabomishInputController.swift:288-292）正 mmap 著被 truncate 的 inode。觸發：IM 面板重新匯入 .cin（CINImportCoordinator 只刪 liu.cin.cache 不刪 liu.bin）時 preheat 正在掃 → 舊 mapping 讀到新 EOF 外的頁 → SIGBUS 殺掉 IM。寫到一半 crash 也會留下 torn bin。

修法：同目錄寫 tmp 再 rename()。

### 8. pkg postinstall 以 root 建 `~/Library/Application Support/Yabomish` — 全新安裝後 IM 寫不進自己的目錄
`tools/release.sh:301-309`

postinstall 跑 root，`mkdir -p "$UD/tables"` 無 chown → 目錄 root:wheel 755。使用者態 IM 寫 freq.db（FreqTracker.swift:42）、下載語料（DataDownloader.swift:164）、匯入 liu.cin（CINImportCoordinator.swift:74）全部 EPERM —— pkg 安裝的學習/字表/語料下載靜默全壞。另外 `$SCRIPT_DIR` 在 postinstall 裡從未定義（pkgbuild 只給 $1-$4）→ :303/:307 兩個 guard 恆 false，yabomish_capture.sh 與 commands.json 在 pkg 安裝下永不部署，`,,ss`/`,,ws`/`,,cs` 直接失效。

修法：mkdir 後 `chown -R "$CONSOLE_USER":staff "$UD"`；SCRIPT_DIR 改 `$(dirname "$0")`。

### 9. ASC 私鑰寫成 world-readable 且永不刪
`tools/release.sh:429-432`

`ASC_PRIVATE_KEY` 以內容傳入時 `printf > $ROOT/build/asc_key.p8`：umask 022 → 644，notarytool 回來後不刪，跨次殘留。本機任何讀取權限都能拿走 App Store Connect key。

修法：`mktemp` + `chmod 600` + `trap 'rm -f' RETURN`。

### 10. 多行 shortcut 內容寫壞 user_shortcuts.txt
`YabomishPrefs/Sources/ShortcutTab.swift:236-246`

`addShortcut()` 只 trim 頭尾，TextEditor 接受內嵌換行；`saveShortcuts()` 原樣寫 `code\tcontent` → 兩行內容變兩條實體行。IM 端 `CINTable.loadTablesFromDir` 逐行 split tab、無 tab 行靜默丟棄 → 重載後 expansion 只剩第一行；更糟的是續行若含 tab（貼上 TSV）會被解析成假 code→content 注入打字 overlay。

修法：add/import 兩處拒收含 `\n`/`\r` 的 content 並 alert，或 escape 換行由 IM 端還原。

### 11. ContextProfile.save() 非原子 — IM/Prefs/sync 三方寫 contexts/*.json 可撕裂
`Shared/ContextProfile.swift:57-61` 與 `YabomishPrefs/Sources/ContextProfile.swift:57-61`（同碼兩份）

`data.write(to:)` 無 `.atomic`。三個寫者：Prefs app（編輯/匯入/新建）、IM（`,,XS`）、yabomish-sync.sh。讀到半寫檔 → decode 失敗 → `loadAll()` compactMap 靜默丟棄、`,,X<code>` 報「未知語境」——使用者語境永久消失。

修法：兩份都加 `options: .atomic`。

### 12. ContextProfile.code 未消毒直接拼路徑 — 匯入/sync/UserDefaults 三路可目錄穿越
`Shared/ContextProfile.swift:35-37`（Prefs 版 :37-39 同）

`contexts/<code>.json` 無驗證。`code` 可經 (a) Prefs 匯入 JSON → `p.save()`、(b) sync 的 contexts/*.json 內部 code 欄位、(c) `currentContext` UserDefaults → `load(code:)`/`delete()` 注入 `../` → 寫/讀/刪 contexts/ 外的檔案。UI 的 2 字元限制（validateNew）只守新建路徑。

修法：model 層 `save()/load()/delete()` 與 `importProfile()` 統一 `^[a-z]{2}$` 驗證。

### 13. NER／萌典詞組的領域排序讀死掉的 pref — 拖曳排序被靜默忽略
`WikiCorpus.swift:228-239`

`suggestAllDomains` 用 `prefs.domainPriority("domain_ner"/"domain_phrases")` 讀 `domain_ner_pri`/`domain_phrases_pri` —— 已無任何寫者（`setDomainPriority` Prefs.swift:522 零呼叫；UI 只寫 `domainOrder`）。NER/萌典永遠 pri 0，SuggestionTab 拖到最後也無效，且 pri-0 三方平手由不穩定 `ranked.sort` 決定。

修法：比照 WBMM bins 用 `DomainOrderManager.allOrderedKeys()` 的位置。

### 14. 螢幕變更 observer 註冊在錯的 notification center — 永遠不觸發
`CandidatePanel.swift:187-190`

`NSApplication.didChangeScreenParametersNotification` 註冊到 `NSWorkspace.shared.notificationCenter`，但 NSApplication 發在 `NotificationCenter.default` → `screenParametersChanged()`(:237) 是死碼。拔螢幕/改解析度時固定面板留在舊座標（可能在螢幕外）直到下次 show()。

修法：改註冊 `NotificationCenter.default`。

---

## 🟡 Warning

| # | 位置 | 問題 |
|---|------|------|
| 15 | `InputEngine.swift:403-411` | VRSF 快選無 pin-mode 守衛：pin 模式下按 v/r/s/f 走 `_commitText(_currentCandidates[idx])` 把字當普通文字 commit（不進 `_pinPicked`），且寫入 `code:"PIN:a"` 垃圾 freq |
| 16 | `InputEngine.swift:793-795` | fuzzy 候選直接賦值 `_currentCandidates`，繞過 `ranker.rank` → .ts/.st 模式不轉換、.sp/.sl 的長短碼過濾/區域降權/領域加權/字頻排序全跳過 |
| 17 | `InputEngine.swift:602-609` | `,,x…` 無條件 return：非語境子指令無「未知命令」回饋；commands.json 裡 x 開頭的自訂指令永遠到不了 `expandText` |
| 18 | `CommaCommandRunner.swift:70-76` | 殘缺 commands.json 項目（open 無 app、shell 無 run、未知 type）`tryExecute` 仍 return true → 吞掉按鍵且壓掉未知命令提示 |
| 19 | `CommaCommandRunner.swift:139-150` | shell watchdog 只送 SIGTERM 且 pipe 從不讀：子進程寫 >64KB 卡住、或 trap TERM → `waitUntilExit()` 永久佔住 GCD 執行緒。需 SIGKILL 升級＋導 /dev/null |
| 20 | `YabomishInputController.swift:313-317` | deactivateServer 的 stale-session 分支只 super，不清自己 client 的 marked text → app A 殘留底線組字；pending freq flush 也跳過 |
| 21 | `CandidatePanel.swift:674-680` | NSCursor push/pop 不平衡：hover 固定面板時改「游標跟隨」→ mouseExited 看即時 isFixed==false 不 pop → openHand 殘留全系統。比照 `dragCursorPushed` 用 flag |
| 22 | `tools/all_platforms.sh:21` | 測試閘門 `grep -q '0 failed'` 是子字串比對：「10 failed」也含 "0 failed" → 失敗數為 10 的倍數時照樣 PASS；且無 pipefail，runner 的 exit code 被管道丟掉 |
| 23 | `tools/yabomish-sync.sh:217` | git_push 對全部 7 個 path `git add`，任一檔案本地不存在 → pathspec fatal + set -e → 該機器 sync 全死。改 `git add -A .` 或逐檔 add |
| 24 | `tools/yabomish-sync.sh:75,172` | pull 直接覆寫 IM 正在讀的 commands.json/user_snippets.json/contexts/*.json（非原子）→ IM 讀到半截 JSON 靜默丟指令/片段。tmp+mv |
| 25 | `tools/yabomish-sync.sh:165-173` | `cp` 跟隨 symlink：惡意 remote 把 commands.json commit 成指向 ~/.ssh/id_rsa 的 symlink → pull 複製目標內容進 SHARE_DIR → 下次 push 外洩。加 `[ ! -L ]` 檢查 |
| 26 | `tools/release.sh:184` | DMG installer 把 `$RES` 插進單引號 shell 字串跑 admin 權限：app 路徑含 `'`（如 `Bob's folder/`）→ quoting 破壞＋root 指令注入面。低可利用性但該修 |
| 27 | `YabomishPrefs/Sources/ContextProfileEditor.swift:145-146` | 編輯器 save() 用目錄序重建 domainOrder → 只是改個名字就把使用者拖好的領域優先序洗掉 |
| 28 | `YabomishPrefs/Sources/SuggestionTab.swift:377-386` | 「重置」只改 @State 不寫 `store.domainOrder` → 切 tab 回來視覺重置被還原，按鈕形同失效 |

## 🟢 Nit

| # | 位置 | 問題 |
|---|------|------|
| 29 | `YabomishInputController.swift:319-323` | deactivateServer 呼叫 exitZhuyin/PinyinMode 會在 IM 已停用後對新焦點 app 彈「繁中」toast |
| 30 | `YabomishInputController.swift:205-235` | `activeScreen(for:)`/`cachedActiveScreen` 零呼叫，~30 行死碼 |
| 31 | `DebugLog.swift:22-37` | debug.log 記 commitText 等實打內容但 0644 權限；且兩 process 共用同檔 rotation 有 race。建 0600＋分檔名 |
| 32 | `Prefs.swift:589-606` | applyProfile ~10 次獨立 defaults.set，跨 process 讀到撕裂 profile（cfprefsd 保證單寫不壞，純暫態） |
| 33 | `CINTable.swift:237-246` | parseBinHeader 不用 section 大小界住 entryCount → 手工 liu.bin 可讓 reverseTableLocked 空轉 40 億次 |
| 34 | `CINTable.swift:366-370` / `CINCompiler.swift:19-20` | Big5 .cin 解碼失敗 → 「匯入成功」但 0 條目（Prefs 成功訊息報 byte 數非 entry 數） |
| 35 | `DataDownloader.swift:186-194` | unzip 直解 supportDir 後只看 bigram.bin marker → 解到一半死掉 = 永久殘缺語料無修復路徑；:87 整檔讀進記憶體做 SHA256 且 CC_LONG 截斷 >4GiB |
| 36 | `FreqTracker.swift:88-96` / `PinnedOrderSection.swift:188-203` | freq.db 雙 process 寫者皆無 busy_timeout 且忽略 step 回傳 → SQLITE_BUSY 靜默丟學習資料/釘選 |
| 37 | `YabomishPrefs/Sources/ShortcutTab.swift:5-7`, `PinnedOrderSection.swift:246-248` | `load(fromByteOffset:)` 對非對齊 offset 是 UB；IM 端同格式已改 `loadUnaligned`（WikiCorpus.swift:569 有註解）→ Prefs 端補齊 |
| 38 | `YabomishPrefs/Sources/PinnedOrderSection.swift:127-131` | cinLookup 先查 bundle liu.bin 再查使用者匯入的 — 與 IM/ShortcutTab 的優先序相反，釘選 UI 顯示的候選與實際打字不符 |
| 39 | `YabomishPrefs/Sources/PrefsStore.swift:188-190` | Prefs app 只發不收 `prefsChanged` → IM 端 `,,SG`/`,,X` 改設定時開著的 prefs 視窗顯示舊值 |
| 40 | `YabomishPrefs/Sources/ContextBar.swift:146-157` | 點語境 chip 不套用 `p.inputMode`（`,,X` 有）→ 選「中式」後其他設定切了但還在打繁體 |
| 41 | `.github/workflows/deploy-docs.yml` | actions 用浮動 major tag 非 SHA pin；`pages:write`/`id-token:write` 掛在 workflow 層讓 build job 也拿到 deploy 權限 |
| 42 | `tools/yabomish-sync.sh:139-141` | token 嵌進 remote URL → ps 可見＋寫進 .git/config。改 `http.extraHeader` |
| 43 | `tools/make_corpus_manifest.py:71-93` | manifest 接受 http:// scheme（SHA pin 限縮為 DoS，但沒理由允許明文傳輸） |
| 44 | `DataDownloader.swift:96-133` | safeUnzip 逐行解析 `zipinfo -l`：檔名含 `\n` 可讓 `..` 續行逃過掃描（unzip 自身有第二層防護＋SHA pin，屬 hardening gap） |

## tools/*.py 語料管線（26 支，節選）

- 🟠 `wiki_word_bigram.py:138,182` — `except Exception: pass` 靜默丟整批 8 行斷詞，無計數無門檻
- 🟠 `wiki_word_bigram.py:44-51,125-167` — resume 用「過濾後列數」回推原始行號，每次續跑重複/漏計 n-gram
- 🟡 `wiki_ngram_pipeline.py:80-84` — iterparse 只清 text 元素，page/revision shell 累積數 GB RSS（wiki_kg/category_extract 有做對）
- 🟡 `wiki_ngram_pipeline.py:126` / `wiki_ner_pipeline.py:76` — 512 字元段 + [CLS]/[SEP] = 514 超過 BERT 512 上限（word_bigram 有正確 cap 510）
- 🟡 `build_ime_db.py:36` — 出貨 db 留 WAL journal_mode，唯讀 bundle 位置開不了（目前無消費者，潛伏）
- 🟡 7 支腳本非原子寫出貨 artifact（terms_*.bin、region_*.txt、corpus_manifest.json、zhuyin_data.json、pinyin_data.json）
- 🟡 `build_region_sets.py:15-24` — glob 不到 NAER CSV 時照樣把 region_tw/cn.txt 覆寫成空檔並 exit 0
- 🟡 `rebuild_domain_bins.py:227` — `list(set)` 順序依 PYTHONHASHSEED → terms_*.bin 不可重現
- 🟡 `build_zhuyin_tables.py:121` — `sorted(z2c[zy][:20])[:5]` 先按字典序截斷再按頻率排 → 高頻字被漏
- 🟢 3 支硬編碼 `/Users/fl/Python/ckip_mlx`；數支 `open()` 無 `encoding=`；`ime_prototype.py` 查不存在的 schema（已 stale）

## 已確認乾淨的面向

- 無硬編碼 secrets/key/token；notary 憑證全走 env
- 簽署流程正確：nested app 先簽、外層後簽、所有寫入在 codesign 前、submit→staple 順序對、hardened runtime+timestamp、entitlements 空 dict
- 語料下載 HTTPS＋bundled manifest SHA-256 pin＋zip-slip 檢查；無 curl|sh
- 無 keystroke/clipboard 外傳；hermes 限 loopback；`,,V` 只在觸發時讀 pasteboard
- 所有 .bin reader 逐次 bounds-check（OOB 回 0）；mmap 生命週期由 Data 持有；WikiCorpus mutation 限主執行緒
- Prefs↔IM 的 suite name、key、型別、預設值、notification 名、contexts/*.json 格式全部對得上
- `install_im`/`do_uninstall` 的 `sudo rm -rf` 目標皆固定字串，無變數展開風險

## 建議修復順序

1. **#2, #3**（打字正確性，使用者每天會踩到）
2. **#1, #4, #12**（注入/穿越面）
3. **#6, #7, #8, #9**（資料損毀/安裝壞掉/金鑰外洩）
4. **#5, #10, #11, #13, #14**（功能靜默失效）
5. 其餘 🟡/🟢 批次處理
