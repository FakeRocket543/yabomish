# 維基百科 NER 實體

- **產出**: `ner_phrases.bin`
- **來源**: 中文維基百科 → ckip-transformers NER pipeline
- **格式**: Parquet `{entity, type, freq}`
- **筆數**: 5,045,971 實體（merge 到 domain bins 時過濾 freq≥10）
- **授權**: CC-BY-SA 3.0（維基百科衍生）
- **Build**: `python3 tools/rebuild_domain_bins.py`（freq≥10 過濾後 merge 到 terms_*.bin）
