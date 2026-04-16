import SwiftUI

/// Unified design tokens for YabomishPrefs.
enum Typo {
    // MARK: - Typography

    // Headings
    static let h1 = Font.title3.bold()              // 頁面大標題
    static let h2 = Font.system(size: 16, weight: .bold)  // 區塊標題
    static let h3 = Font.system(size: 13, weight: .bold) // 子標題

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

    // MARK: - Colors（媽祖廟五色）

    static let cyan   = Color(red: 143/255, green: 172/255, blue: 191/255) // #8FADBF 青灰
    static let gold   = Color(red: 242/255, green: 211/255, blue: 121/255) // #F2D479 金黃
    static let orange = Color(red: 242/255, green: 141/255, blue:  53/255) // #F28D35 橘
    static let deep   = Color(red: 242/255, green: 122/255, blue:  53/255) // #F27B35 深橘
    static let red    = Color(red: 242/255, green:  64/255, blue:  48/255) // #F24130 朱紅

    // Semantic colors
    static let ok      = Color.green                  // 可用 ✓
    static let warn    = Color.orange                 // 警告 ⚠️
    static let cardOff = Color.primary.opacity(0.05)  // 卡片停用背景
    static let strokeOff = Color.primary.opacity(0.15) // 卡片停用邊框
}

/// 區塊分隔線：上下 padding + 橫線，用在每個 Label(.h2) 前面
struct SectionDivider: View {
    var body: some View {
        Divider().padding(.vertical, 6)
    }
}
