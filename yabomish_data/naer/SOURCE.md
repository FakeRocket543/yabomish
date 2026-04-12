# NAER 國家教育研究院專業詞典

- **產出**: `terms_agri.bin`, `terms_art.bin`, `terms_bio.bin`, ... (20 個領域)
- **來源**: 國家教育研究院「樂詞網」
- **格式**: CSV，欄位因領域而異，通常含：ID, 英文名稱, 中文名稱, 中國大陸譯名
- **筆數**: 378 個 CSV 檔案，涵蓋 20 個學科領域
- **授權**: 政府開放資料
- **URL**: https://terms.naer.edu.tw/
- **Build**: `python3 tools/rebuild_domain_bins.py`（純 NAER + 維基 freq≥10 merge）
- **兩岸對照**: 含「兩岸」的 CSV 用於產生 `region_tw.txt` / `region_cn.txt`
