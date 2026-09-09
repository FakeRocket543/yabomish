---
title: "安裝與設定"
order: 1
---


---

## 系統需求

| 項目 | 需求 |
|------|------|
| 作業系統 | macOS 14.0 Sonoma 或以上 |
| 處理器 | Apple Silicon（M1 / M2 / M3 / M4） |
| 字表 | 嘸蝦米 CIN 字表（`liu.cin`，使用者自行取得） |

> **注意**：Yabomish 目前僅支援 Apple Silicon。採用 DMG 安裝包（方式一）不需要任何開發工具；
> 使用原始碼安裝（方式二）需先安裝 Xcode Command Line Tools：
>
> ```bash
> xcode-select --install
> ```

---

## 安裝步驟

### 方式一：DMG 安裝包（推薦）

從 [GitHub Releases](https://github.com/FakeRocket543/yabomish/releases) 下載安裝包（各約 2.8MB），雙擊打開：

| 安裝包 | 內容 | 首次下載語料 |
|--------|------|------------|
| **Yabomish-精簡.dmg** | 輸入法＋設定程式＋基礎聯想（萌典／維基／新聞、成語、兩岸用詞） | 約 15MB |
| **Yabomish-全量.dmg** | 同上＋28 部專業詞典＋一般詞庫 | 約 100MB |

流程：雙擊「安裝 Yabomish.app」→ 管理員授權 → 自動安裝輸入法與設定程式、重啟輸入法，並**自動開啟系統設定的輸入方式列表**（直接按 + 加入 Yabomish）。安裝訊息依系統語言顯示繁中／簡中／英文。

語料在首次打字時自動下載（SHA-256 驗證，存放於 `~/Library/Application Support/Yabomish/`），下載完成即時生效；下載前打字、查碼、繁簡轉換均可正常使用，離線也不受影響。

### 方式二：原始碼安裝（開發者）

### 1. 取得原始碼

```bash
git clone https://github.com/FakeRocket543/yabomish.git
cd yabomish
```

### 2. 執行安裝腳本

```bash
./yabomish.sh
```

選擇安裝模式：

| 選項 | 說明 | 大小 |
|------|------|------|
| **1) 完整安裝** | 基礎聯想 + 28 專業詞典 | ~98MB |
| **2) 精簡安裝** | 基礎聯想，不含專業詞典 | ~18MB |
| **3) 極簡安裝** | 無聯想、無詞庫，僅打字＋查碼＋繁簡轉換＋字頻排序 | ~2MB |

> 精簡版包含字級聯想、詞級語料（萌典/維基/新聞）、成語、兩岸用詞切換等基礎功能。專業詞典可之後重裝補上。
> 「極簡」僅原始碼安裝可選，不隨 Release DMG 發佈。

### 3. 安裝過程

腳本會自動完成以下工作：

1. **編譯**輸入法本體（`YabomishIM.app`）與設定程式（`YabomishPrefs.app`）
2. 將 `YabomishIM.app` 安裝到 `/Library/Input Methods/`
3. 將 `YabomishPrefs.app` 安裝到 `/Applications/`
4. 自動套用既有的**蝦頭方向**與**狀態列名稱**偏好（可在 YabomishPrefs → 外觀調整）
5. 部署使用者層資源（`commands.json` 範例、擴充表目錄）

安裝完成後，終端機會提示下一步操作。


---

## 加入輸入方式

1. 開啟 **系統設定** → **鍵盤** → **輸入方式**
2. 點選左下角 **＋**
3. 搜尋 **Yabomish**
4. 選取後點 **加入**

加入後，按 **Ctrl + Space**（或你設定的輸入法切換鍵）即可切換到 Yabomish。

> **提示**：如果列表中找不到 Yabomish，請先登出再登入，或重新開機讓系統偵測新安裝的輸入法。

---

## 匯入字表

### 首次匯入

第一次切換到 Yabomish 時，會自動彈出引導畫面，引導你匯入 `liu.cin` 字表。

### 手動匯入

也可以從設定程式匯入：

1. 開啟 **YabomishPrefs.app**（或從狀態列選單進入設定）
2. 切到 **輸入** 分頁
3. 點選 **匯入字表⋯**
4. 選擇你的 `liu.cin` 檔案

### 編譯與隱私

- 字表匯入後會在**裝置上**編譯為 `.bin` 二進位格式（mmap zero-copy 載入，啟動更快）
- **不上傳、不外流**——所有資料留在本機


### 擴充表

除了 `.cin` 主表，Yabomish 也支援 `.txt` 擴充表：

- 擴充表放在 `~/Library/Application Support/Yabomish/tables/` 目錄
- 格式為 tab 分隔：`編碼<Tab>內容`
- 修改後輸入 `,,RL` + Space 即可即時重載（一併重載自訂指令與 snippets）
- Emoji 聯想不是擴充表——由語料檔 `emoji_char_map.json` 驅動，隨安裝或首次語料下載提供

---

## 更新

當有新版本時：

- **DMG 安裝**：下載新版的 DMG，重新執行一次「安裝 Yabomish.app」即可（覆蓋安裝，使用者資料與字表保留）。
- **原始碼安裝**：

```bash
cd yabomish
git pull
./yabomish.sh
```

選擇 **`1) 編譯 + 安裝`**——重新編譯並安裝，保留你的字頻資料和設定（`4) 快速重裝偏好設定` 只重裝設定程式）。

---

## 移除

```bash
cd yabomish
./yabomish.sh
```

選擇 **`5) 移除 Yabomish`**，腳本會清除輸入法和設定程式。

> **提示**：移除前建議先到系統設定將 Yabomish 從輸入方式中移除。使用者資料（字表、字頻、擴充表）位於 `~/Library/Application Support/Yabomish/`（舊版安裝可能在 `~/Library/YabomishIM/`）；移除腳本會詢問「一併刪除使用者資料？」，確認後自動清除。

---
