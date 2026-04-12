import SwiftUI

struct DomainTab: View {
    @Bindable var store: PrefsStore
    @State private var generalOrder: [DomainEntry] = []
    @State private var proOrder: [DomainEntry] = []
    @State private var saved = false

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("點擊卡片啟用／停用詞庫。拖拉調整優先順序。")
                    .font(.callout).foregroundStyle(.secondary)

                sectionHeader("一般詞庫", icon: "text.book.closed")
                gridSection(entries: $generalOrder, color: .blue)

                sectionHeader("專業詞典", icon: "graduationcap")
                gridSection(entries: $proOrder, color: .orange)

                HStack {
                    Spacer()
                    if saved { Text("已套用 ✓").foregroundStyle(.green).transition(.opacity) }
                    Button("套用") { apply() }.controlSize(.large)
                }
            }
            .padding(20)
        }
        .onAppear { loadOrder() }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.headline)
    }

    @ViewBuilder
    private func gridSection(entries: Binding<[DomainEntry]>, color: Color) -> some View {
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
            let cellSize: CGFloat = 100
            let col = max(0, Int(location.x / cellSize))
            let row = max(0, Int(location.y / cellSize))
            let gridCols = max(1, Int((NSScreen.main?.frame.width ?? 600) / cellSize))
            let destIdx = min(arr.count, row * gridCols + col)
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
