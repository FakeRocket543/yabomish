import SwiftUI

/// 單選卡片按鈕：圖示＋標題＋描述，選中時強調色底色／邊框與右上角勾勾。
/// 統一 AppearanceTab／InputTab／SuggestionTab 原本各自複製的卡片樣式（視覺完全一致）。
/// 參數說明：
/// - icon：SF Symbol 名稱；iconText：直接以文字當圖示（如「漢」），使用襯線粗體（兩者擇一）
/// - showCheckmark：選中時是否顯示右上角勾勾
/// - highlightText：未選中時標題／描述跟著淡化（regionCard 樣式）
/// - minHeight：卡片最小高度；labelLineLimit：標題行數上限
struct SelectableCardView: View {
    let label: String
    let desc: String
    let selected: Bool
    var icon: String? = nil
    var iconText: String? = nil
    var showCheckmark: Bool = true
    var highlightText: Bool = false
    var minHeight: CGFloat = 88
    var labelLineLimit: Int = 2
    let action: () -> Void

    /// highlightText 模式下（regionCard 樣式）標題／描述會隨選中狀態淡化。
    /// 沿用層級樣式（.primary／.secondary／.tertiary），與原本 .foregroundStyle(.secondary) 語意一致。
    private var labelColor: HierarchicalShapeStyle {
        if highlightText { return selected ? .primary : .secondary }
        return .primary
    }

    private var descColor: HierarchicalShapeStyle {
        if highlightText { return selected ? .secondary : .tertiary }
        return .secondary
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 5) {
                    if let iconText {
                        Text(iconText)
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .foregroundStyle(selected ? Typo.accent : .secondary)
                    } else if let icon {
                        Image(systemName: icon)
                            .font(Typo.cardIcon)
                            .foregroundStyle(selected ? Typo.accent : .secondary)
                    }
                    Text(label)
                        .font(Typo.cardTitle)
                        .foregroundStyle(labelColor)
                        .lineLimit(labelLineLimit)
                        .multilineTextAlignment(.center)
                    Text(desc)
                        .font(Typo.cardDesc)
                        .foregroundStyle(descColor)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: minHeight)
                if selected && showCheckmark {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Typo.accent)
                        .padding(6)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Typo.accent.opacity(0.18) : Typo.cardOff))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Typo.accent.opacity(0.7) : Typo.strokeOff,
                        lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(selected ? "已選擇" : "未選擇")
    }
}
