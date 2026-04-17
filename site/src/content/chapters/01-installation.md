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
| 開發工具 | Xcode Command Line Tools |
| 字表 | 嘸蝦米 CIN 字表（`liu.cin`，使用者自行取得） |

> **注意**：Yabomish 目前僅支援 Apple Silicon。如尚未安裝 Xcode Command Line Tools，請在終端機執行：
>
> ```bash
> xcode-select --install
> ```

---

## 安裝步驟

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

> 精簡版包含字級聯想、詞級語料（萌典/維基/新聞）、成語、兩岸用詞切換等基礎功能。專業詞典可之後重裝補上。

### 3. 安裝過程

腳本會自動完成以下工作：

1. **編譯**輸入法本體（`YabomishIM.app`）與設定程式（`YabomishPrefs.app`）
2. 將 `YabomishIM.app` 安裝到 `/Library/Input Methods/`
3. 將 `YabomishPrefs.app` 安裝到 `/Applications/`
4. 詢問**蝦頭方向**（狀態列圖示朝向）
5. 詢問**狀態列名稱**（顯示在選單列的文字）

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

- 擴充表放在 `~/Library/YabomishIM/tables/` 目錄
- 格式為 tab 分隔：`編碼<Tab>內容`
- 安裝時預設包含 Emoji 聯想擴充表
- 修改後輸入 `,,RL` + Space 即可即時重載

---

## 更新

當有新版本時：

```bash
cd yabomish
git pull
./yabomish.sh
```

選擇 **`4) 快速重裝`**——只重新編譯並安裝，保留你的字頻資料和設定。

---

## 移除

```bash
cd yabomish
./yabomish.sh
```

選擇 **`6) 移除 Yabomish`**，腳本會清除輸入法和設定程式。

> **提示**：移除前建議先到系統設定將 Yabomish 從輸入方式中移除。使用者資料（字頻、擴充表）位於 `~/Library/YabomishIM/`，移除腳本不會自動刪除，如需清除請手動刪除該目錄。

---
