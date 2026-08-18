# Kaomoji 顏文字資料

- **用途**: Yabomish 外掛式 snippets（`Plugins/kaomoji/snippets.json`）
- **來源**: [kaomojikan/kaomoji-data](https://github.com/kaomojikan/kaomoji-data)
- **授權**: MIT（顏文字字元本身為 Unicode，屬公有領域；分類與整理為 MIT）
- **處理**: 已過濾多行 ASCII Art、長度 > 60、重複項目，只保留單行日式顏文字
- **編碼**: 短碼以 `;` 開頭（避免與嘸蝦米字根衝突），後接 1 碼分類與 2 碼 base-26 序號，共 4 碼（與 `maxCodeLength` 相容）
