import SwiftUI

struct DomainTab: View {
    @Bindable var store: PrefsStore
    @State private var generalOrder: [DomainEntry] = []
    @State private var proOrder: [DomainEntry] = []
    @State private var saved = false

    private let columns = [GridItem(.adaptive(minimum: 145))]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("拖拉卡片調整順序，越靠左越優先。勾選啟用。")
                .font(.callout).foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("詞庫", entries: $generalOrder, color: .blue)
                    section("專業詞典", entries: $proOrder, color: .orange)
                }
                .padding(.horizontal, 4)
            }

            HStack {
                Spacer()
                if saved { Text("已套用 ✓").foregroundStyle(.green).transition(.opacity) }
                Button("套用") { apply() }
            }
        }
        .padding()
        .onAppear { loadOrder() }
    }

    @ViewBuilder
    private func section(_ title: String, entries: Binding<[DomainEntry]>, color: Color) -> some View {
        Text(title).font(.headline)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(entries.wrappedValue) { entry in
                DomainCardView(
                    entry: entry,
                    isEnabled: Binding(
                        get: { store.domainEnabled(entry.id) },
                        set: { store.setDomainEnabled(entry.id, $0) }
                    ),
                    color: color
                )
            }
        }
        .dropDestination(for: String.self) { items, location in
            guard let draggedID = items.first else { return false }
            var arr = entries.wrappedValue
            guard let srcIdx = arr.firstIndex(where: { $0.id == draggedID }) else { return false }
            let item = arr.remove(at: srcIdx)
            // Estimate destination index from drop x position
            let colWidth: CGFloat = 150
            let cols = max(1, Int(location.x / colWidth))
            let row = max(0, Int(location.y / 52))
            let gridCols = max(1, Int(NSScreen.main?.frame.width ?? 600) / 150)
            let destIdx = min(arr.count, row * gridCols + cols)
            arr.insert(item, at: destIdx)
            entries.wrappedValue = arr
            return true
        }
    }

    private func loadOrder() {
        let saved = store.domainOrder
        if saved.isEmpty {
            generalOrder = DomainData.generalDomains
            proOrder = DomainData.proDomains
        } else {
            let lookup = Dictionary(uniqueKeysWithValues: DomainData.allDomains.map { ($0.id, $0) })
            var gen = [DomainEntry](); var pro = [DomainEntry]()
            for key in saved {
                guard let e = lookup[key] else { continue }
                switch e.group {
                case .general: gen.append(e)
                case .professional: pro.append(e)
                }
            }
            // Append any missing entries
            for e in DomainData.generalDomains where !gen.contains(where: { $0.id == e.id }) { gen.append(e) }
            for e in DomainData.proDomains where !pro.contains(where: { $0.id == e.id }) { pro.append(e) }
            generalOrder = gen
            proOrder = pro
        }
    }

    private func apply() {
        store.domainOrder = (generalOrder + proOrder).map(\.id)
        store.postChange()
        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { saved = false }
        }
    }
}
