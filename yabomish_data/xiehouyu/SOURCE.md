# 歇後語

- **產出**: `terms_xiehouyu.bin`
- **來源**: chinese-xinhua（中華新華字典資料庫）
- **格式**: JSON `[{riddle, answer}, ...]`，已 OpenCC s2t 轉繁體
- **筆數**: 14,032 筆
- **授權**: MIT
- **URL**: https://github.com/pwxcoo/chinese-xinhua
- **Build**: `python3 tools/build_xiehouyu.py`
- **觸發**: 前半句 prefix → 後半句 answer
