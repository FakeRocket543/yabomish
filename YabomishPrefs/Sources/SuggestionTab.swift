import SwiftUI

private struct SuggestLayer: Identifiable {
    let id: String
    let label: String
    let icon: String
    let desc: String
}

private let allLayers = [
    SuggestLayer(id: "word", label: "詞級語料", icon: "text.book.closed", desc: "萌典/維基/新聞"),
    SuggestLayer(id: "domain", label: "詞庫", icon: "books.vertical", desc: "專業詞典聯想"),
    SuggestLayer(id: "char", label: "字級聯想", icon: "character.textbox", desc: "bigram / trigram"),
]

private struct CorpusEntry: Identifiable {
    let id: String
    let label: String
    let icon: String
    let desc: String
}

private let corpusEntries = [
    CorpusEntry(id: "moedict", label: "萌典", icon: "character.book.closed", desc: "教育部詞組"),
    CorpusEntry(id: "wiki", label: "維基", icon: "globe.asia.australia", desc: "維基百科斷詞"),
    CorpusEntry(id: "news", label: "新聞", icon: "newspaper", desc: "台灣新聞斷詞"),
]

struct SuggestionTab: View {
    @Bindable var store: PrefsStore
    @State private var layerOrder: [SuggestLayer] = []
    @State private var generalOrder: [DomainEntry] = []
    @State private var proOrder: [DomainEntry] = []
    @State private var saved = false
    @State private var showResetConfirm = false

    private let threeColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    private let domainColumns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 1. Hint
                Text("拖拉調整優先順序。點擊啟用／停用。")
                    .font(.callout).foregroundStyle(.secondary)

                // 2. Layer order
                Label("聯想層順序", systemImage: "square.3.layers.3d").font(.headline)
                LazyVGrid(columns: threeColumns, spacing: 8) {
                    ForEach(layerOrder) { layer in
                        layerCard(layer)
                    }
                }
                .dropDestination(for: String.self) { items, location in
                    guard let draggedID = items.first,
                          let srcIdx = layerOrder.firstIndex(where: { $0.id == draggedID }) else { return false }
                    let item = layerOrder.remove(at: srcIdx)
                    let col = max(0, min(2, Int(location.x / 160)))
                    layerOrder.insert(item, at: min(layerOrder.count, col))
                    return true
                }

                // 3. Word corpus source
                Label("詞級語料來源", systemImage: "text.book.closed").font(.headline)
                LazyVGrid(columns: threeColumns, spacing: 8) {
                    ForEach(corpusEntries) { entry in
                        corpusCard(entry)
                    }
                }

                // 4. General domains
                Label("一般詞庫", systemImage: "books.vertical").font(.headline)
                domainGrid(entries: $generalOrder, color: .blue)

                // 5. Pro domains
                // 5. Pro domains — compact chip layout
                Label("專業詞典（樂詞網＋維基百科）", systemImage: "graduationcap").font(.headline)
                proChipGrid(entries: $proOrder)

                // 6. Bottom bar
                HStack {
                    Button("重置") { showResetConfirm = true }
                    Spacer()
                    if saved { Text("已套用 ✓").foregroundStyle(.green).transition(.opacity) }
                    Button("套用") { apply() }.controlSize(.large)
                }
            }
            .padding(20)
        }
        .onAppear { loadOrder(); loadDomains() }
        .alert("確定重置聯想設定？", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) { resetDefaults() }
        }
    }

    // MARK: - Layer card

    @ViewBuilder
    private func layerCard(_ layer: SuggestLayer) -> some View {
        let enabled = layer.id == "char" ? store.charSuggest : true
        Button { if layer.id == "char" { store.charSuggest.toggle() } } label: {
            VStack(spacing: 5) {
                Image(systemName: layer.icon)
                    .font(.system(size: 26))
                    .foregroundStyle(enabled ? Color.accentColor : .secondary)
                Text(layer.label)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(layer.desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(enabled ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(enabled ? Color.accentColor.opacity(0.7) : Color(nsColor: .separatorColor).opacity(0.6),
                        lineWidth: enabled ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .draggable(layer.id)
    }

    // MARK: - Corpus card (radio-style single select, green)

    @ViewBuilder
    private func corpusCard(_ entry: CorpusEntry) -> some View {
        let selected = store.wordCorpus == entry.id
        Button { store.wordCorpus = entry.id } label: {
            VStack(spacing: 5) {
                Image(systemName: entry.icon)
                    .font(.system(size: 26))
                    .foregroundStyle(selected ? .green : .secondary)
                Text(entry.label)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(entry.desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.green.opacity(0.18) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Color.green.opacity(0.7) : Color(nsColor: .separatorColor).opacity(0.6),
                        lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Domain grid (reuses DomainCardView)

    @ViewBuilder
    private func domainGrid(entries: Binding<[DomainEntry]>, color: Color) -> some View {
        LazyVGrid(columns: domainColumns, spacing: 8) {
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

    // MARK: - Pro domain chips (compact layout)

    private let chipColumns = [GridItem(.adaptive(minimum: 110), spacing: 6)]

    @ViewBuilder
    private func proChipGrid(entries: Binding<[DomainEntry]>) -> some View {
        LazyVGrid(columns: chipColumns, spacing: 6) {
            ForEach(entries.wrappedValue) { entry in
                proChip(entry)
            }
        }
        .dropDestination(for: String.self) { items, location in
            guard let draggedID = items.first else { return false }
            var arr = entries.wrappedValue
            guard let srcIdx = arr.firstIndex(where: { $0.id == draggedID }) else { return false }
            let item = arr.remove(at: srcIdx)
            let cellW: CGFloat = 116
            let col = max(0, Int(location.x / cellW))
            let row = max(0, Int(location.y / 38))
            let gridCols = max(1, Int(540 / cellW))
            let destIdx = min(arr.count, row * gridCols + col)
            arr.insert(item, at: destIdx)
            entries.wrappedValue = arr
            return true
        }
    }

    @ViewBuilder
    private func proChip(_ entry: DomainEntry) -> some View {
        let on = store.domainEnabled(entry.id)
        let count = DomainData.binEntryCount(file: entry.file)
        Button { store.setDomainEnabled(entry.id, !on) } label: {
            HStack(spacing: 4) {
                Image(systemName: entry.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(on ? .orange : .secondary)
                Text(entry.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(on ? .primary : .secondary)
                if count > 0 {
                    Text(count >= 10000 ? String(format: "%.0fw", Double(count)/10000) : "\(count)")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(on ? .secondary : .tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(on ? Color.orange.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(on ? Color.orange.opacity(0.7) : Color(nsColor: .separatorColor).opacity(0.6),
                            lineWidth: on ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .draggable(entry.id)
    }

    // MARK: - Load / Apply / Reset

    private func loadOrder() {
        let strategy = store.suggestStrategy
        let lookup = Dictionary(uniqueKeysWithValues: allLayers.map { ($0.id, $0) })
        let order: [String]
        switch strategy {
        case "domain": order = ["domain", "word", "char"]
        case "char":   order = ["char", "word", "domain"]
        default:       order = ["word", "domain", "char"]
        }
        layerOrder = order.compactMap { lookup[$0] }
    }

    private func loadDomains() {
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
        // Save layer strategy
        let ids = layerOrder.map(\.id)
        if ids.first == "domain" { store.suggestStrategy = "domain" }
        else if ids.first == "char" { store.suggestStrategy = "char" }
        else { store.suggestStrategy = "general" }

        // Save domain order
        store.domainOrder = (generalOrder + proOrder).map(\.id)

        store.postChange()
        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { saved = false } }
    }

    private func resetDefaults() {
        store.suggestStrategy = "general"
        store.wordCorpus = "wiki"
        store.charSuggest = true
        loadOrder()
        generalOrder = DomainData.generalDomains
        proOrder = DomainData.proDomains
    }
}
