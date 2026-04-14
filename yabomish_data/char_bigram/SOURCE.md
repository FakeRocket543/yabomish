# 字級 Bigram / Trigram

- **產出**: `bigram.bin`, `trigram.bin`
- **來源**: 中文維基百科 → 字級 n-gram 統計
- **格式**: Parquet
- **授權**: CC-BY-SA 3.0（維基百科衍生）
- **用途**: 字級聯想建議（Layer 1 靜態部分）
- **備註**: `wiki_trigram_general.parquet`（104MB）不含在 repo 中，需自行執行 `python3 tools/wiki_ngram_pipeline.py` 產生
