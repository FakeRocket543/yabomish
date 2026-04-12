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
                    .font(.system(size: 26))
                    .foregroundStyle(isEnabled ? color : .secondary)

                Text(entry.label)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text(entry.desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if count > 0 {
                    Text(formatCount(count))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 100, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isEnabled ? color.opacity(0.12) : Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isEnabled ? color.opacity(0.5) : Color(nsColor: .separatorColor), lineWidth: isEnabled ? 1.5 : 0.5)
            )
            .opacity(isEnabled ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .draggable(entry.id)
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 10000 { return String(format: "%.1f 萬筆", Double(n) / 10000.0) }
        return "\(n) 筆"
    }
}
