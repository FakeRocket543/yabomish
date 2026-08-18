# Yabomish Sync — v1 檔案同步規格

三平台個人化資料漫遊。v1 = 快照 + last-writer-wins（LWW）；v2 預留 oplog 合併語意（payload 換軌、運輸層不變）。

## 佈局（R2 prefix：`yabomish-sync/`）

```
yabomish-sync/
├── manifest.json          # 同步清單 + 各檔 mtime/hash（權威索引）
├── commands.json          # ,, 指令庫（v2 schema: text/shell/open）
├── char_freq.json         # 字頻快照
└── contexts/              # 情境設定檔（ch/df/tc/tw）
    ├── ch.json
    ├── df.json
    ├── tc.json
    └── tw.json
```

## manifest.json

```json
{
  "schema": 1,
  "updated_at": "2026-08-18T14:00:00Z",
  "updated_by": "mac-v0.3.60",
  "files": {
    "commands.json":  { "sha256": "…", "mtime": 1755513600 },
    "char_freq.json": { "sha256": "…", "mtime": 1755513600 }
  }
}
```

- 下載端：remote mtime > local mtime 且 hash 不同 → 抓檔覆蓋本地
- 上傳端：本地 mtime > remote mtime → put + 更新 manifest（讀-改-寫，衝突機率低；v2 換 oplog 消除）
- LWW 語意：同時編輯輸一邊。commands/contexts 可接受；字頻 v2 走 oplog

## 平台角色

| 平台 | 讀 | 寫 | transport |
|---|---|---|---|
| macOS | 本地 `~/Library/Application Support/Yabomish/` | 同左 | vos3 daemon（已部署） |
| iOS | app group `group.com.yabomishim.keyboard/` | 容器 app 匯入 | URLSession 直連 R2 REST |
| Android | app filesDir | 容器 activity 匯入 | OkHttp / WorkManager |

## 引擎介面（不變式）

輸入法 process **永遠不碰網路**：只讀本地檔。同步一律在容器 app / daemon 做，完成後呼叫既有 `reload()` 進效。

## 安全

- R2 bucket 私有；iOS/Android 直連需 AWS SigV4（access key 存 Keychain/Keystore）
- 不含打字內容記錄——只同步設定與統計
