import Foundation

/// CSV 欄位跳脫：內容含逗號、引號或換行時，以引號包夾並把內部引號加倍，
/// 避免匯出的 CSV 欄位錯位。LookupHistorySection 與 ShortcutTab 共用。
func csvEscape(_ s: String) -> String {
    if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return s
}
