# 維基百科詞級 Bigram

- **產出**: `word_ngram.bin`
- **來源**: 中文維基百科 dump → ckip-transformers 斷詞 → 詞級 bigram 統計
- **格式**: JSON `{前詞: [後詞1, 後詞2, ...]}`，按頻率排序
- **筆數**: 85,382 clean keys（已過濾英文/數字/wiki markup）
- **授權**: CC-BY-SA 3.0（維基百科衍生）
- **Build**: `python3 tools/build_wbmm.py bigram_json data/word_bigram.json YabomishIM/Resources/word_ngram.bin`
- **清洗**: `_is_clean_key()` 排除 tab、英文、數字開頭、wiki markup
