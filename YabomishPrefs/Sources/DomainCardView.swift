import SwiftUI

struct DomainCardView: View {
    let entry: DomainEntry
    @Binding var isEnabled: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 4)
            Toggle(isOn: $isEnabled) {
                let count = DomainData.binEntryCount(file: entry.file)
                if count > 0 {
                    Text("\(entry.label) (\(count))").lineLimit(1)
                } else {
                    Text(entry.label).lineLimit(1)
                }
            }.toggleStyle(.checkbox)
        }
        .padding(.trailing, 8)
        .frame(width: 140, height: 44)
        .background(RoundedRectangle(cornerRadius: 10).fill(isEnabled ? Color(nsColor: .controlBackgroundColor) : Color.gray.opacity(0.3)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(isEnabled ? 1.0 : 0.5)
        .draggable(entry.id)
    }
}
