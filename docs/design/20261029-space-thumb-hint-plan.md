# Space Thumb Hint（角落靜態色塊）實作計畫

日期：2026-10-29  
狀態：計畫，未實作  
預設：關閉

## 目標

根據最後輸入碼的左右手，顯示對側拇指按 Space 的低干擾提示：
角落靜態半透明色塊，預設關閉，可調整透明度/大小。

## 手左右分類

使用硬體 keyCode（layout-independent），左/右手集合：

- 左手：`q w e r t a s d f g z x c v b` 對應 keyCode
- 右手：`y u i o p h j k l n m`

最後一碼若為左手 → 右下色塊亮；右手 → 左下色塊亮。

## UI 設計

- 候選窗角落顯示直徑 6–8pt 半透明圓點/小方塊
- 顏色：
  - 左手碼 → 右下提示色（例如青綠）
  - 右手碼 → 左下提示色（例如橘黃）
- 不閃爍、不動畫；透明度可調（預設 0.35）
- 僅組字中且候選窗顯示時出現

## 偏好

- `spaceThumbHint: Bool`（預設 false）
- `spaceThumbHintOpacity: Double`（預設 0.35）
- `spaceThumbHintSize: Double`（預設 8pt）

## 實作位置

- `IMEPreferences` 新增三個 key
- `InputEngine` 暴露 `lastKeyHand: .left/.right/.none`
- `YabomishInputController.showNewEngineCandidatePanel` 傳入 hand side
- `CandidatePanel` 繪製角落色塊

## 測試

1. 左手碼 → 右下亮；右手碼 → 左下亮
2. 偏好關閉時不顯示
3. 透明度/大小調整生效
4. MINIMAL build 編譯通過

## 非目標

- 不做閃爍動畫
- 不做聲音/震動
- 不做教學模式（可後續）