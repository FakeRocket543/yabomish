# NAER 國家教育研究院專業詞典

- **產出**: 28 個 `terms_*.bin`
- **來源**: 國家教育研究院「樂詞網」
- **格式**: CSV，欄位因領域而異，通常含：ID, 英文名稱, 中文名稱, 中國大陸譯名
- **筆數**: 378 個 CSV 檔案，217 個子分類，對應 28 個 domain bin
- **清洗**: 分號/逗號拆分多義詞、去括號注釋、去英文、詞長限 3-8 字
- **授權**: 政府開放資料
- **URL**: https://terms.naer.edu.tw/
- **Build**: `python3 tools/rebuild_domain_bins.py`（NAER parquet + 維基 freq≥50 merge）
- **兩岸對照**: 含「兩岸」的 CSV 用於產生 `region_tw.txt` / `region_cn.txt`
- **Domain 分類**:
  - 資訊工程：it、ee、power、mech、eng（土木水利）、aero（航太）、nuclear（核能）、textile（紡織食品）
  - 自然科學：math、phy、chem、bio（動物生態）、botany（植物）、fish（魚類）、material、agri
  - 商業醫學：biz、med
  - 人文社科：law、edu、media、social、govt、art
  - 地理軍事：geo、placename_intl、marine、mil
