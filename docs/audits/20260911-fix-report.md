# Yabomish 修復報告 — 2026-09-11（對應 20260911-full-review.md）

流程：7 個修復切片並行 → 雙 target typecheck → 138 tests → shellcheck/py_compile → 2 位 reviewer 對全 diff 找迴歸 → 迴歸修完再驗證 → `-O` 完整建置（yabomish.sh 選項 2）成功。

## 結果

44 項發現：**43 修復、1 項接受不修**（#44 zipinfo 換行逃逸 — 僅 hardening gap，SHA pin＋unzip 自身 `..` 消毒仍在）。

### 🔴 Blocker（2/2 修復）

| # | 修復 |
|---|------|
| 1 | `install_quick_action.py` — 改 `subprocess.run(["osascript","-e",script,"--",msg])`，文字走 `on run argv`，全程無 shell；已實測含 `"`/`` ` ``/`$()` 的注入字串原樣顯示不執行 |
| 2 | `InputEngine.handleEnter` — pin 模式分支先於 commit：清 `_isPinMode/_pinCode/_pinPicked`＋`_resetComposing()`，不再把 `PIN:abc` 字面 commit、不寫垃圾 freq |

### 🟠 Critical（12/12 修復）

| # | 修復 |
|---|------|
| 3 | `_eatNextSpace` 整個移除（ivar/set/check/clear 全刪）— flag 本來就到不了 engine，幻影空白＋吞空白一併消失 |
| 4 | `open` 型指令改 `Process`+argv（`/usr/bin/open -a`），不經 `zsh -c`；shell 型保留但 watchdog 升級（見 #19） |
| 5 | `ContextProfileCommands` 刪 `profile.inputMode = snap.inputMode` — snapshot 本來就沒有 mode 來源，保留已存值 |
| 6 | **CINM v1**：header byte 7 = 版本；valIdx 改 8B/entry（u32 off + u16 cnt + u16 reserved），>65k scalar 的表不再截斷；reader 雙版本相容，Prefs 端 `PinnedOrderSection.cinLookup` 同步支援 v1 |
| 7 | `CINCompiler` 寫同目錄 `.tmp-<uuid>` 再 `replaceItemAt`/`moveItem` — mmap 舊 inode 不受影響，無 SIGBUS、無半寫檔 |
| 8 | pkg postinstall：`chown -R "$CONSOLE_USER":staff "$UD"`；`SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` — capture script/commands.json 恢復部署 |
| 9 | ASC key 改 `mktemp`＋`chmod 600`＋`trap RETURN rm` — 不再落 `build/asc_key.p8` 644 |
| 10 | `ShortcutTab.addShortcut`/`importShortcuts` 拒收含 `\n`/`\r` 的 content 並 alert；匯入對 CRLF/純 CR 列計數略過 |
| 11 | 兩份 `ContextProfile.save()` 皆 `.atomic` |
| 12 | `ContextProfile.isValidCode`（`^[a-z]{2}$`）守住 save/load/delete；`ContextBar.importProfile` 同步擋無效碼＋reservedCodes；`validateNew` 補 a-z 規則（見迴歸 R2） |
| 13 | NER/萌典詞組改用 dense 優先序：`reloadDomains` 以 `nextPri` 計數器只數載入成功的來源，`loadNER`/`loadPhrases` 回傳 Bool — 與 domainBins 同尺，拖曳順序真正生效 |
| 14 | 螢幕變更 observer 改註冊 `NotificationCenter.default` |

### 🟡 Warning（14/14 修復）

#15 VRSF 加 `guard !_isPinMode`；#16 fuzzy 結果走 `ranker.rank`（見迴歸 R1）；#17 `,,x` nil dispatch 落回正常管線；#18 `tryExecute` 對殘缺項目回 false；#19 watchdog 改 nullDevice＋SIGTERM→SIGKILL 升級；#20 stale-session deactivateServer 仍清自己 client 的 marked text；#21 `hoverCursorPushed` flag 對稱 push/pop；#22 測試閘門 `, 0 failed$`＋pipefail（見迴歸 R4）；#23 `git add -A .`；#24 pull 走 tmp+mv＋失敗清 tmp；#25 拒 symlink；#26 安裝路徑含 `'` 直接拒絕；#27 編輯器沿用已存 domainOrder；#28 重置寫回 `store.domainOrder`。

### 🟢 Nit（15/16 修復）

#29 `isDeactivating` 靜音收編期間 toast；#30 刪 `activeScreen`/`cachedActiveScreen` 死碼；#31 debug.log 0600（跨 process rotation race 未改 — debug-only，接受）；#32 `applyProfile` 批次寫＋單次 refresh＋post；#33 `entryCount` 依 section 大小 clamp；#34 Big5 fallback 解碼（Prefs 匯入 UI 的「0 條目」大聲報錯未加 — 記錄）；#35 staging 目錄解壓＋marker 最後移入＋串流 SHA-256；#36 雙方 `busy_timeout`＋step 回傳檢查；#37 `loadUnaligned`；#38 liu.bin 使用者優先；#39 PrefsStore 觀察 prefsChanged＋generation bump；#40 `pendingInputMode` 握手（ContextBar 寫鍵→IM refreshSnapshot 讀走→activateServer 排空 `switchToMode`）；#41 actions SHA pin＋job 層級權限；#42 token 改 `http.extraHeader`；#43 manifest 僅 https。**#44 不修**（理由如上）。

### tools/*.py（14 項全修）

wiki_word_bigram：失敗計數＋門檻中止、resume 改記原始行號 checkpoint（見迴歸 R3）；wiki_ngram/ner：iterparse 全清、段長 510；build_ime_db：journal_mode=DELETE；7 支出貨 artifact 改 tmp+`os.replace`；build_region_sets 空 glob 拒寫；rebuild_domain_bins `sorted(set)`；build_zhuyin_tables 全排序取 top5；fix_zhuyin_reading_order `check=True`＋全歷史註解；4 支補 `encoding='utf-8'`；build_news_ngram `errors='replace'`；ime_prototype/poc_char_embedding 標 STALE＋缺檔明確報錯；ckip_mlx 路徑改 `CKIP_MLX_PATH` env。

## 自我 review 抓到的迴歸（全數已修）

| # | 迴歸 | 修法 |
|---|------|------|
| R1 | fuzzy 走 rank() 後 .sp/.sl 的 membership 過濾把鄰鍵候選全丟（打錯字救援失效） | `rank(..., fuzzy:)` 參數，fuzzy 時跳過 .sp/.sl 過濾 |
| R2 | `save()` 的 `^[a-z]{2}$` 讓 Prefs 新建 sheet 接受的 "a1" 類碼靜默存檔失敗 | `validateNew` 同步 `isValidCode`，兩側一致 |
| R3 | wiki_word_bigram：save_partial 先於 save_checkpoint，crash 窗口讓續跑重複計數 | checkpoint 記 `rows`/`shards`，resume 對帳：partial 多寫→截斷重寫、merge 完未記→丟棄殘留 partial、shard 少於記錄→拒絕續跑 |
| R4 | `pipefail` 讓 `cmd \| grep -q` 管線 SIGPIPE（macos_build 成功也 fail） | 全部改 `out=$(cmd)` 先收完整輸出再 `grep <<<"$out"` |
| R5 | malformed 指令名若撞上 modeMap key（t/s/sp…）會誤切模式 | `tryExecute` false 後查 `commands[cmd]`，存在→「格式錯誤」toast，不落 modeMap |
| R6 | NER/phrases 用 sparse orderedKeys 位置 vs bins 用 dense → 停用/缺檔時順序分歧 | dense `nextPri` 計數器（併入 #13 修法） |
| R7 | 我對 yabomish-sync.sh 的 anchor-remap 編輯誤刪 `git_push` 的 `local email`/`GIT_AUTHOR_*` | 已復原，diff 對 HEAD 無身份列變更 |

## 驗證

- `swiftc -typecheck`：YabomishIM、YabomishPrefs 皆 0 診斷
- `Tests/run_tests.sh`：**138 passed, 0 failed**
- `yabomish.sh` 選項 2 完整 `-O` 建置：YabomishIM.app [full] 110M＋YabomishPrefs.app 成功
- `bash -n`/`zsh -n`/`py_compile`/YAML parse：全部編輯過的腳本乾淨
- shellcheck 殘留 3 個既有警告（SC2046×2、SC2010×1）— 非本次引入，未動
- FixData 的獨立驗證：CINM v1 round-trip 38/38（含 70k 條目、v0 相容、entryCount clamp、Big5、原子寫）；串流 SHA-256 與 `shasum -a 256` 位元一致（含 4.6GiB sparse）；freq.db busy_timeout 競態煙測 50/50 筆落盤

## 已知殘留（接受）

- #44 zipinfo 換行逃逸：SHA pin＋unzip 自身消毒仍在，屬 hardening gap
- debug.log 跨 process rotation race：debug-mode only
- Big5 .cin 可解碼但 Prefs 匯入 UI 尚未對「0 條目」大聲報錯
- iOS 測試閘門 `grep ' 0 failures'`：前導空白使 "10 failures" 不匹配，實際安全
