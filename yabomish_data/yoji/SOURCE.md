# 日本四字熟語（yoji）

## 產出
- `yoji.bin`（WBMM 格式）

## 來源
- [MDict](https://www.mdict.cn/) 日本語辭典資料，抽取四字熟語
- 排除與中文成語典（`chengyu.bin`）及萌典詞組（`phrases.bin`）重疊的詞條

## 授權
- 衍生整理（原始辭典資料經篩選去重）

## 說明
保留日本獨有的四字熟語，如「一期一會」「以心伝心」「臨機応変」等。
與中文共通的成語（如「一石二鳥」）已排除，避免與 chengyu.bin 重複。

## Build
```bash
python3 tools/build_wbmm.py prefix data/yoji.txt YabomishIM/Resources/yoji.bin
```
