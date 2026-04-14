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
    @State private var showResetConfirm = false

    private let threeColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    private let domainColumns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    private var hasCorpus: Bool {
        DomainData.binEntryCount(file: "bigram") > 0 ||
        DomainData.allDomains.contains { DomainData.binEntryCount(file: $0.file) > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !hasCorpus {
                    VStack(spacing: 8) {
                        Image(systemName: "shippingbox").font(.system(size: 32)).foregroundStyle(.secondary)
                        Text("目前為精簡安裝，未包含聯想語料。")
                            .font(Typo.body)
                        Text("重新執行 yabomish.sh 選擇「完整安裝」即可啟用聯想功能。")
                            .font(Typo.hint).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                // 1. Hint
                HStack(spacing: 4) {
                    Image(systemName: "hand.draw").foregroundStyle(.secondary)
                    Text("拖拉卡片調整優先順序。點擊啟用／停用。")
                        .font(Typo.hint).foregroundStyle(.secondary)
                }

                // 2. Layer order
                Label("聯想層順序", systemImage: "square.3.layers.3d").font(Typo.h2)
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
                    saveStrategy()
                    return true
                }

                // 3. Word corpus source
                Label("詞級語料來源", systemImage: "text.book.closed").font(Typo.h2)
                LazyVGrid(columns: threeColumns, spacing: 8) {
                    ForEach(corpusEntries) { entry in
                        corpusCard(entry)
                    }
                }

                // 4. General domains
                Label("一般詞庫", systemImage: "books.vertical").font(Typo.h2)
                domainGrid(entries: $generalOrder, color: Typo.cyan)

                // 5. Pro domains — compact chip layout, collapsed by default
                DisclosureGroup {
                    Text("點擊啟用／停用。拖拉調整建議優先順序。")
                        .font(Typo.hint).foregroundStyle(.secondary)
                    proChipGrid(entries: $proOrder)
                } label: {
                    HStack(spacing: 6) {
                        Text("專業詞典（樂詞網＋維基百科）")
                        let n = proOrder.filter { store.domainEnabled($0.id) }.count
                        if n > 0 {
                            Text("\(n)/\(proOrder.count)")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Typo.orange.opacity(0.25)))
                                .foregroundStyle(Typo.orange)
                        }
                    }
                }
                .font(Typo.h2)

                // 6. Bottom bar
                // 6. Bottom bar
                HStack {
                    Button("重置") { showResetConfirm = true }
                    Spacer()
                }
                } // end else (hasCorpus)
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
                    .font(Typo.cardIcon)
                    .foregroundStyle(enabled ? Typo.deep : .secondary)
                Text(layer.label)
                    .font(Typo.cardTitle)
                    .lineLimit(1)
                Text(layer.desc)
                    .font(Typo.cardDesc)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(enabled ? Typo.deep.opacity(0.18) : Typo.cardOff))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(enabled ? Typo.deep.opacity(0.7) : Typo.strokeOff,
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
                    .font(Typo.cardIcon)
                    .foregroundStyle(selected ? Typo.red : .secondary)
                Text(entry.label)
                    .font(Typo.cardTitle)
                    .lineLimit(1)
                Text(entry.desc)
                    .font(Typo.cardDesc)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Typo.red.opacity(0.18) : Typo.cardOff))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Typo.red.opacity(0.7) : Typo.strokeOff,
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
            saveDomainOrder()
            return true
        }
    }

    // MARK: - Pro domain chips (compact layout)

    private let chipColumns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    @ViewBuilder
    private func proChipGrid(entries: Binding<[DomainEntry]>) -> some View {
        let grouped = Dictionary(grouping: entries.wrappedValue, by: \.category)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(DomainData.proCategoryOrder, id: \.self) { cat in
                if let items = grouped[cat], !items.isEmpty {
                    Text(DomainData.categoryLabel(cat))
                        .font(Typo.h3).foregroundStyle(.secondary)
                        .padding(.top, 4)
                    LazyVGrid(columns: chipColumns, spacing: 6) {
                        ForEach(items) { entry in
                            proChip(entry)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func proChip(_ entry: DomainEntry) -> some View {
        let on = store.domainEnabled(entry.id)
        let count = DomainData.binEntryCount(file: entry.file)
        Button { store.setDomainEnabled(entry.id, !on) } label: {
            HStack(spacing: 6) {
                Image(systemName: entry.icon)
                    .font(Typo.chipIcon)
                    .frame(width: 18)
                    .foregroundStyle(on ? Typo.orange : .secondary)
                Text(entry.label)
                    .font(Typo.chipTitle)
                    .foregroundStyle(on ? .primary : .secondary)
                Spacer()
                if count > 0 {
                    Text(formatChipCount(count))
                        .font(Typo.chipBadge)
                        .foregroundStyle(on ? .secondary : .tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(on ? Typo.orange.opacity(0.18) : Typo.cardOff)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(on ? Typo.orange.opacity(0.7) : Typo.strokeOff,
                            lineWidth: on ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .draggable(entry.id)
    }

    private func formatChipCount(_ n: Int) -> String {
        if n >= 10000 { return String(format: "%.1f 萬", Double(n) / 10000.0) }
        return "\(n) 筆"
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

    private func saveStrategy() {
        let ids = layerOrder.map(\.id)
        if ids.first == "domain" { store.suggestStrategy = "domain" }
        else if ids.first == "char" { store.suggestStrategy = "char" }
        else { store.suggestStrategy = "general" }
    }

    private func saveDomainOrder() {
        store.domainOrder = (generalOrder + proOrder).map(\.id)
    }

    private func resetDefaults() {
        store.suggestStrategy = "general"
        store.wordCorpus = "wiki"
        store.charSuggest = true
        store.regionVariant = "tw"
        loadOrder()
        generalOrder = DomainData.generalDomains
        proOrder = DomainData.proDomains
    }
}
