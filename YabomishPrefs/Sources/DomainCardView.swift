#if !MINIMAL
import SwiftUI

struct DomainCardView: View {
    let entry: DomainEntry
    @Binding var isEnabled: Bool
    let color: Color

    private var count: Int { DomainData.binEntryCount(file: entry.file) }

    var body: some View {
        Button { isEnabled.toggle() } label: {
            VStack(spacing: 5) {
                Image(systemName: entry.icon)
                    .font(Typo.cardIcon)
                    .foregroundStyle(isEnabled ? color : .secondary)

                Text(entry.label)
                    .font(Typo.cardTitle)
                    .lineLimit(1)

                Text(entry.desc)
                    .font(Typo.cardDesc)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if count > 0 {
                    Text(formatCount(count))
                        .font(Typo.cardBadge)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minWidth: 112, minHeight: 88)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isEnabled ? color.opacity(0.18) : Typo.cardOff)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isEnabled ? color.opacity(0.7) : Typo.strokeOff,
                            lineWidth: isEnabled ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .draggable(entry.id)
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 10000 { return String(format: "%.1f 萬筆", Double(n) / 10000.0) }
        return "\(n) 筆"
    }
}
#endif
