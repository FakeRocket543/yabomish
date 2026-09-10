# 錯誤狀況筆記 — 發佈流程（打包／簽署／公證）

> 2026-09-10 v0.3.64 發佈實作遇到的錯誤與修法。之後跑 `tools/release.sh` 前先掃一遍本檔。

---

## 1. 公證 Invalid：巢狀 App 缺時間戳與 Hardened Runtime

**現象**：`notarytool submit --wait` 回 `status: Invalid`，log 顯示 DMG 內兩個 binary 各有三條錯誤：

```
Yabomish-精簡.dmg/安裝 Yabomish.app/Contents/Resources/YabomishIM.app/Contents/MacOS/YabomishIM
  - The signature of the binary is invalid.
  - The signature does not include a secure timestamp.
  - The executable does not have the hardened runtime enabled.
（YabomishPrefs 同）
```

**根因**：`安裝 Yabomish.app` 的 Resources/ 裡還有 YabomishIM.app、YabomishPrefs.app 兩個巢狀 App。`codesign --deep` 對外層 bundle 簽署時**不會把 `--options runtime`／`--timestamp` 套用到巢狀 bundle**——Apple 文件本就建議產品散佈要逐層由內向外簽。原本 release.sh 只對外層 `--deep` 簽一次，巢狀 App 等於掛著「有身分但沒硬化」的簽章。

**修法**（已修入 release.sh `create_installer`）：巢狀的先逐一簽、最後才簽外層，外層不 `--deep`：

```bash
codesign --force --deep --sign "$DEVELOPER_ID" \
    --entitlements tools/YabomishIM.entitlements \
    --options runtime --timestamp "$APP/Contents/Resources/YabomishIM.app"
codesign --force --deep --sign "$DEVELOPER_ID" \
    --options runtime --timestamp "$APP/Contents/Resources/YabomishPrefs.app"
codesign --force --sign "$DEVELOPER_ID" \
    --options runtime --timestamp "$APP"
```

**查錯指令**（記 job id 就能看到完整 log 與出錯檔案路徑）：

```bash
xcrun notarytool log <submission-id> --keychain-profile yabomish-notary
```

---

## 2. `notarytool staple` 不是合法指令

**現象**：`xcrun notarytool staple xxx.dmg` → `Error: 2 unexpected arguments`。

**根因**：staple 是獨立工具 `stapler` 的子指令，不是 notarytool 的。release.sh 原本就寫錯（`xcrun notarytool staple`）——因為公證憑證從未設定過，這段是從沒執行過的死碼，設好憑證第一次跑就爆。

**修法**（已修入 release.sh）：`xcrun notarytool staple` → `xcrun stapler staple`（兩處）。

---

## 3. DMG 內嵌的語料 manifest 過期（打包順序錯誤）

**現象**：v0.3.64 的 DMG 打完，內嵌 `corpus_manifest.json` 仍指向 `v0.3.59` 的語料 zip——使用者首次打字會下載到舊版語料。

**根因**：manifest 是在「Release 上傳語料 zip 之後」才能重產，但打包在重產**之前**就跑了。正確順序：

```
語料 zip 備妥（build/yabomish-corpus-*.zip＋build/corpus-hashes.txt）
→ make_corpus_manifest.py --tag v0.3.64 --sha256 <lite> --full-sha256 <full>
→ release.sh lite／full 打包（manifest 帶進 bundle）
→ 公證＋staple
→ push＋tag＋gh release create（上傳 DMG＋語料 zip）
```

**檢查法**：打包後掛載 DMG 直接看：

```bash
hdiutil attach -nobrowse -quiet "Yabomish-精簡.dmg" && \
cat "/Volumes/Yabomish/安裝 Yabomish.app/Contents/Resources/YabomishIM.app/Contents/Resources/corpus_manifest.json"; \
hdiutil detach -quiet "/Volumes/Yabomish"
```

---

## 4. （非錯誤）spctl 對 DMG 本體回 rejected 是正常的

`spctl --assess --type open xxx.dmg` 會回 `rejected / source=no usable signature`——DMG 是磁碟映像檔、沒有 App 簽章，**這不是失敗**。要驗的是裡面的 App：

```bash
hdiutil attach -nobrowse -quiet xxx.dmg
spctl --assess -vv "/Volumes/Yabomish/安裝 Yabomish.app"   # 應 accepted / Notarized Developer ID
xcrun stapler validate xxx.dmg                              # 應 The validate action worked!
hdiutil detach -quiet "/Volumes/Yabomish"
```

---

## 5. 原始碼安裝（fresh clone）的語料依賴 Release 存在

**現象**：全新 `git clone` + `./yabomish.sh` 裝完，打字／查碼／繁簡都正常，但**聯想語料下載 404**（在那個版本的 GitHub Release 發佈之前）。

**根因**：語料 `*.bin` 在 `.gitignore`——repo 本身不含語料。fresh clone 的 `1) 完整` 與 `2) 精簡` 實際等價（只是選單心理安慰），語料一律走 `DataDownloader` 依 `corpus_manifest.json` 的 URL 下載（預設 `corpusVariant=lite`，約 15MB）；URL 指向 `releases/download/vX/...`，**Release 還沒發佈就 404**。失敗為靜默記錄、下次啟用重試，不影響打字。

**正確時序**：先發佈 Release（含語料 zip），原始碼使用者才有聯想。也因此**換版時若更新 manifest 指到新版 URL，必須同時把新版語料 zip 上傳上去**，否則原始碼安裝者的聯想會壞到舊 Release 被刪為止。

**尺寸宣稱**：`~98MB/~18MB` 只在本地已備語料的開發機成立；README／手冊／選單已加註（2026-09-10）。

---

## 環境速記

- 公證憑證 profile：`yabomish-notary`（Apple ID （Apple ID 存於本機 Keychain）／Team 2SYA986D7H，存於 Keychain）
- 簽署身分：`Developer ID Application: CHIH HSIAN LIN (2SYA986D7H)`（release.sh 自動偵測）
- 無 Developer ID Installer 憑證 → PKG 永遠跳過（DMG 為唯一散佈物）；要出 PKG 需先在 Apple Developer 產生 Installer 憑證
- 公證來回約 1–3 分鐘／包；送審後 bits 有變（重打包）就要重新 submit＋staple
