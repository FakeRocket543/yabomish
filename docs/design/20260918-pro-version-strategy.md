# Pro 版產品策略 — $10 尊榮感定位

日期：2026-09-18
狀態：策略討論定稿，待包裝實作

## 核心洞見

yabomish 的差異化不在輸入法本體，在三層疊在狀態機上的結構：

```
InputEngine = mode 狀態機
  ├─ 組字 mode（預設）：cinTable 查表 → 候選 → commit
  ├─ 查碼 modes：ZH 注音 / PYT·PYS 拼音 / TO 同音 / PIN 固定
  └─ ,, mode：兩層 dispatcher
        ├─ 內建層：硬編碼（RS/RL/PIN/ZH/…/B/F）
        └─ 資料層：commands.json → text/shell/open/hermes
```

第三層 Hermes 是擷取面（單向出口，fire-and-forget），不是指令回饋。這個三層結構對嘸蝦米**零依賴**——真正的 moat 是 `,,` 層不是字表。

## 產權盤點（2026-09-18 確認）

| 專案 | 擁有者 | 授權 |
|---|---|---|
| yabomish（macOS IME） | 本人 | MIT，GitHub 公開 |
| yabomish_cahiers（練習套件） | 本人 | 無 LICENSE＝閉源，僅 git.lcn.tw |
| ohmybias-ios | Daniel Kao (plateaukao) | MIT Shared/ 的下游，本人是貢獻者非擁有者 |

## 定價定位：$10 尊榮感

不追規模，追的是價格本身作為定位訊號。$10 是衝動購買區間又非零——宣示價值。精品 indie app 打法：賣的不是功能是身份（懂門道的人）。

尊榮感產品的成本在產品表面：簽章 DMG、license 啟動、landing page、上手文件——codebase 已有 pro 級水準，包裝是零。license 用 honor key 即可，防盜版投入不划算。

買家需自備正版嘸蝦米字表——對尊榮感客群反而加分，門檻即篩選。

## 產品結構

**免費層 = 公開 MIT repo（DIY build），零額外維護。**

**$10 套件 = 簽章 DMG + cahiers 練習套件 + 支持工匠身份。**

- cahiers 是套件中**唯一獨佔**的元件：IME 的 `,,` 功能全在 MIT repo，誰都能編；練習機閉源且別處拿不到
- cahiers 資料迴路是現成賣點：`freq.db` 查字歷史 → 弱點字出題——「你打的每個字都在幫練習機出題」
- OhMyBias 是行銷素材非競品：「Shared/ 引擎乾淨到第三方直接拿去出了 iOS 鍵盤」是可移植性的第三方背書
- 出貨形式：一個 DMG 兩個 app；文件須註明練習機依賴 IME 已安裝（讀 liu.bin/freq.db/bigram.bin）

## cahiers 為何不開源（定論）

「怕被抄」是假議題——此 niche 的抄襲者池極小，且創意早已公開在 README；license 保護不了想法。

真正的理由：cahiers 沒有 yabomish 不能用（讀 liu.bin），開源不創造新用戶，只讓既有用戶免費——而免費替代品出現等同套件獨佔性蒸發。`build.sh` 一條指令就是完整產品。

不對稱敘事是好故事：「引擎開源、練習機是工坊出品」——核心的可移植性全給（MIT），工匠的打磨留著。

單向門原則：閉源隨時能開，開了收不回。重新考慮開源的時機：套件策略失敗想換影響力時、維護勞務價值超過獨佔性時（讓社群養）。

## 待辦

- [ ] DMG 打包流程（YabomishIM.app + YabomishPractice.app 同包）
- [ ] license/啟動機制（honor key 級別即可）
- [ ] landing page——docs/design 裡的設計論述可直接改寫為文案
- [ ] cahiers 說明文件補「需先安裝 Yabomish 輸入法」
