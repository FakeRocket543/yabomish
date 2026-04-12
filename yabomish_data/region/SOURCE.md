# 兩岸用詞標記

- **產出**: `region_tw.txt`, `region_cn.txt`
- **來源**: NAER 兩岸對照名詞系列 CSV
- **格式**: TXT，一行一詞，sorted, deduplicated
- **筆數**: TW 82,016 / CN 82,210
- **授權**: 政府開放資料
- **Build**: `python3 tools/build_region_sets.py`
- **用途**: runtime 降權——使用者選「臺灣正體」時，CN 詞降權；反之亦然
