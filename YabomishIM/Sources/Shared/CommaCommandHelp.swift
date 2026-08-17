import Foundation

/// Static help text for the `,,H` command and shared command descriptions.
/// Extracted from InputEngine to keep the engine a pure state machine.
enum CommaCommandHelp {
    static func helpText(suggestCommands: Bool) -> String {
        let sgxHelp = suggestCommands
            ? "• ,,SG 聯想開關\n• ,,Xxx 切換語境  ,,XS 儲存  ,,XI 顯示\n"
            : ""
        return """
        【Yabomish 輸入法 使用指南】

        ▎基本輸入
        • 輸入字根碼後按空白鍵送出
        • V/R/S/F 快速選第 2/3/4/5 個候選字
        • 數字鍵 1-9 選字（多候選時）

        ▎空白鍵手勢
        • 左右滑：循環切換 Yabomish→英文→數字→符號
        • 上滑：中↔英快速切換
        • 右上滑：注音查碼
        • 左上滑：同音字查詢

        ▎鍵盤切換
        • [123]：切到數字符號頁
        • [符]：切到數字頁（無蝦米第三行）
        • [嘸/英]：從數字符號頁回到字母頁

        ▎特殊指令（輸入 ,, 開頭）
        • ,,T 繁體  ,,S 簡體  ,,J 日文
        • ,,SP 速成  ,,SL 慢打
        • ,,TS 繁→簡  ,,ST 簡→繁
        • ,,ZH 注音查碼  ,,TO 同音字
        • ,,PYS 拼音(簡)  ,,PYT 拼音(繁)
        • ,,RS 重置字頻  ,,RL 重載字表
        • ,,PIN 固定同碼字排序  ,,UNPINx 解除
        \(sgxHelp)• ,,C 顯示目前模式
        • ,,H 顯示本說明

        ▎剪貼簿處理
        • ,,V 貼上純文字（去格式）
        • ,,VT 貼上簡→繁  ,,VS 貼上繁→簡

        ▎自訂指令
        • 設定檔：~/Library/Application Support/Yabomish/commands.json
        • ,,RL 重載字表及自訂指令

        ▎候選字區
        • 空閒時顯示目前輸入法模式
        • 空閒時左方出現貼上鍵（剪貼簿有內容時）
        • 候選字超過 10 個時可展開為網格

        ▎高度調整
        • 拖拉候選字區上緣可調整鍵盤高度
        • 設定頁可用滑桿調整（以螢幕百分比儲存）
        """
    }

    /// Mode map shared by dispatch and switchToMode.
    static let modeMap: [String: InputEngine.InputMode] = [
        "t": .t, "s": .s, "sp": .sp, "sl": .sl, "ts": .ts, "st": .st, "j": .j
    ]
}
