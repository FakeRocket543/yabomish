# Yabomish 語料資料集

本目錄收錄 Yabomish 輸入法使用的所有明碼（人類可讀）語料來源。
每個子目錄對應一個或多個 WBMM binary（`.bin`），附 `SOURCE.md` 說明來源、做法、格式與授權。

## 總表

| 目錄 | 產出 bin | 筆數 | 來源 | 授權 |
|------|---------|------|------|------|
| `word_ngram/` | `word_ngram.bin` | 85K keys | 中文維基百科 ckip 斷詞 bigram | CC-BY-SA 3.0 |
| `word_news/` | `word_news.bin` | 492K 詞 | 國家教育研究院 新聞語料庫 | 政府開放資料 |
| `phrases/` | `phrases.bin` | — | 萌典（教育部國語辭典） | CC0 |
| `chengyu/` | `chengyu.bin` | 33K 成語 | 教育部成語典 | 政府開放資料 |
| `yoji/` | `yoji.bin` | — | MDict 日本語辭典（排除中文成語重疊） | 衍生整理 |
| `ner/` | `ner_phrases.bin` | 5M 實體 (filtered) | 中文維基百科 NER | CC-BY-SA 3.0 |
| `jingjing/` | `terms_jingjing.bin` | 188 詞條 | 自建晶晶體詞典 | 自有 |
| `cn_slang/` | `terms_cn_slang.bin` | 3,047 詞條 | 中國網路流行語（繁體化） | 衍生整理 |
| `xiehouyu/` | `terms_xiehouyu.bin` | 14,032 筆 | chinese-xinhua (中華新華字典) | MIT |
| `kautian/` | `terms_kautian.bin` | 428 俗諺 | 教育部台灣閩南語常用詞辭典 | 政府開放資料 |
| `hakka/` | `terms_hakka.bin` | 19,570 詞目 | 教育部臺灣客語辭典（六腔） | 政府開放資料 |
| `korean/` | `terms_korean.bin` | 33,414 漢字詞 | Kengdic 韓英辭典 | MPL 2.0 / LGPL 2.0+ |
| `placename/` | `terms_placename.bin` | 519 地名 | 教育部本土語言標注臺灣地名 | CC-BY 3.0 TW |
| `placename_intl/` | `terms_placename_intl.bin` | 53K 譯名 | 國家教育研究院 樂詞網 | 政府開放資料 |
| `ttg/` | `terms_ttg.bin` | 4,553 術語 | 教育部臺灣台語學科術語 | CC-BY 3.0 TW |
| `naer/` | `terms_*.bin` ×28 | 378 CSV | 國家教育研究院樂詞網 | 政府開放資料 |
| `region/` | `region_tw.txt` / `region_cn.txt` | 82K / 82K | NAER 兩岸對照名詞 | 政府開放資料 |
| `char_bigram/` | `bigram.bin` / `trigram.bin` | — | 維基百科字級 n-gram | CC-BY-SA 3.0 |
| `emoji/` | (runtime 用) | — | CLDR emoji 中文標注 | Unicode License |

## 授權摘要

- **政府開放資料**：教育部、國家教育研究院釋出，可自由使用，需標明來源。
- **CC-BY-SA 3.0**：維基百科衍生資料，需標明來源，衍生作品同授權。
- **CC-BY 3.0 TW**：教育部地名/學科術語，需標明來源。
- **MIT**：chinese-xinhua 歇後語，保留 MIT 聲明即可。
- **MPL 2.0 / LGPL 2.0+**：Kengdic 韓語辭典，雙授權擇一。MPL 2.0 要求修改的 MPL 檔案開源（build script 已開源）。
- **Unicode License**：CLDR emoji 資料。

## Build 指令

每個語料都有對應的 `tools/build_*.py` 腳本：

```bash
python3 tools/build_wbmm.py bigram_json data/word_bigram.json YabomishIM/Resources/word_ngram.bin
python3 tools/build_wbmm.py news data/news_word_freq.tsv YabomishIM/Resources/word_news.bin
python3 tools/build_kautian.py
python3 tools/build_hakka.py
python3 tools/build_korean_hanja.py
python3 tools/build_xiehouyu.py
python3 tools/build_placename.py
python3 tools/build_region_sets.py
python3 tools/rebuild_domain_bins.py
```

## WBMM 格式

所有 `.bin` 檔案使用自訂的 WBMM（Word-Based Multi-Map）格式：
- Header: `WBMM` magic + key count + key index offset + value index offset
- Key index: 每筆 12 bytes（string offset, string length, value start, value count）
- Value index: 每筆 6 bytes（string offset, string length）
- String blob: UTF-8 encoded strings
- 查詢方式：mmap + binary search，微秒級
