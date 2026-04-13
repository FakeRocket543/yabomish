# 萌典詞組（phrases）

## 產出
- `phrases.bin`（PHMM 格式）

## 來源
- [萌典](https://www.moedict.tw/)（教育部國語辭典資料）
- 原始資料：[g0v/moedict-data](https://github.com/g0v/moedict-data)

## 授權
- CC0（公眾領域貢獻宣告）

## 說明
萌典詞組用於聯想輸入的第二層（詞級語料），提供字→詞的 prefix match 補全。
例如輸入「台」後建議「台灣」「台北」「台中」等。

## Build
```bash
python3 tools/build_wbmm.py prefix data/moedict_phrases.txt YabomishIM/Resources/phrases.bin
```
