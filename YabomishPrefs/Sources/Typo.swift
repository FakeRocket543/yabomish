import SwiftUI

/// Unified design tokens for YabomishPrefs.
enum Typo {
    // MARK: - Typography

    // Headings
    static let h1 = Font.title3.bold()              // 頁面大標題
    static let h2 = Font.system(size: 17, weight: .bold)  // 區塊標題
    static let h3 = Font.system(size: 14, weight: .semibold) // 子標題

    // Body
    static let body     = Font.system(size: 14)
    static let bodyMono = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let hint     = Font.system(size: 14)
    static let caption  = Font.system(size: 12)

    // Cards
    static let cardIcon  = Font.system(size: 24)
    static let cardTitle = Font.system(size: 14, weight: .semibold)
    static let cardDesc  = Font.system(size: 13)
    static let cardBadge = Font.system(size: 12).monospacedDigit()

    // Chips
    static let chipIcon  = Font.system(size: 14)
    static let chipTitle = Font.system(size: 14, weight: .medium)
    static let chipBadge = Font.system(size: 12).monospacedDigit()

    // MARK: - Colors (semantic)

    /// 強調色（選中、開啟、按鈕）
    static let accent   = Color.accentColor
    /// 成功（已匯入、可用）
    static let success  = Color.green
    /// 警告（提醒、覆蓋）
    static let warning  = Color.orange
    /// 錯誤（刪除、衝突）
    static let error    = Color.red

    static let cardOff   = Color.primary.opacity(0.05)  // 卡片停用背景
    static let strokeOff = Color.primary.opacity(0.15)  // 卡片停用邊框
}

/// 區塊分隔線：上下 padding + 橫線，用在每個 Label(.h2) 前面
struct SectionDivider: View {
    var body: some View {
        Divider().padding(.vertical, 6)
    }
}
