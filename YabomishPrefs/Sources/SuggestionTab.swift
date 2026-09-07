#if !MINIMAL
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
    SuggestLayer(id: "emoji", label: "Emoji 聯想", icon: "face.smiling", desc: "依最後送字聯想"),
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
    /// 拖放落點換算用網格寬度。量測掛在 background（不佔版面）——
    /// 不能用 GeometryReader 包住網格：它在 ScrollView 裡會塌陷成極小
    /// 高度，內容溢出與後續區塊重疊。
    @State private var layerGridWidth: CGFloat = 0

    private let threeColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    private let layerColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    private let domainColumns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    private var hasProDomains: Bool {
        DomainData.proDomains.contains { DomainData.binEntryCount(file: $0.file) > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("語境切換", systemImage: "arrow.triangle.swap").font(Typo.h2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("一鍵切換輸入模式、聯想策略、詞庫組合與地區用詞。")
                        .font(Typo.body)
                    Text("點擊切換 ｜ 右鍵編輯或複製 ｜ 輸入法中 ,,X + 碼 切換（如 ,,XTW）")
                        .font(Typo.hint).foregroundStyle(.secondary)
                    Text(",,XRS 重置為預設 ｜ ,,XS 儲存當前設定 ｜ ,,XI 顯示當前語境")
                        .font(Typo.hint).foregroundStyle(.secondary)
                }
                ContextBar(store: store)
                SectionDivider()
                Label("用詞習慣", systemImage: "map").font(Typo.h2)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    regionCard("tw", label: "臺灣用詞", icon: "漢", desc: "臺灣慣用詞優先")
                    regionCard("cn", label: "中式用詞", icon: "汉", desc: "中式慣用詞優先")
                }

                SectionDivider()
                if !hasProDomains {
                    VStack(spacing: 8) {
                        Image(systemName: "shippingbox").font(.system(size: 32)).foregroundStyle(.secondary)
                        Text("目前為精簡安裝，未包含專業詞典。")
                            .font(Typo.body)
                        Text("重新執行 yabomish.sh 選擇「完整安裝」即可啟用 28 個專業詞典。")
                            .font(Typo.hint).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                // 1. Hint
                HStack(spacing: 4) {
                    Image(systemName: "hand.draw").foregroundStyle(.secondary)
                    Text("拖拉卡片調整優先順序。點擊啟用／停用。")
                        .font(Typo.hint).foregroundStyle(.secondary)
                }

                // 2. Layer order
                Label("聯想層順序", systemImage: "square.3.layers.3d").font(Typo.h2)
                Text("Emoji 排最前時一定看得到；排其餘位置則文字聯想優先，聯想列有空位才顯示。")
                    .font(Typo.hint).foregroundStyle(.secondary)
                LazyVGrid(columns: layerColumns, spacing: 8) {
                    ForEach(layerOrder) { layer in
                        layerCard(layer)
                    }
                }
                .background {
                    GeometryReader { g in
                        Color.clear
                            .onAppear { layerGridWidth = g.size.width }
                            .onChange(of: g.size.width) { _, new in layerGridWidth = new }
                    }
                }
                .dropDestination(for: String.self) { items, location in
                    guard let draggedID = items.first,
                          let srcIdx = layerOrder.firstIndex(where: { $0.id == draggedID }) else { return false }
                    let item = layerOrder.remove(at: srcIdx)
                    let col = layerGridWidth > 0
                        ? max(0, min(3, Int(location.x / (layerGridWidth / 4))))
                        : min(3, layerOrder.count)
                    layerOrder.insert(item, at: min(layerOrder.count, col))
                    saveStrategy()
                    return true
                }

                // 3. Word corpus source
                SectionDivider()
                Label("詞級語料來源", systemImage: "text.book.closed").font(Typo.h2)
                LazyVGrid(columns: threeColumns, spacing: 8) {
                    ForEach(corpusEntries) { entry in
                        corpusCard(entry)
                    }
                }

                // 4. General domains
                SectionDivider()
                Label("一般詞庫", systemImage: "books.vertical").font(Typo.h2)
                domainGrid(entries: $generalOrder, color: Typo.accent)

                // 5. Pro domains — compact chip layout, collapsed by default
                SectionDivider()
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
                                .background(Capsule().fill(Typo.accent.opacity(0.25)))
                                .foregroundStyle(Typo.accent)
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
        let enabled = switch layer.id {
        case "char":  store.charSuggest
        case "emoji": store.emojiSuggest
        default:      true
        }
        SelectableCardView(label: layer.label, desc: layer.desc,
                           selected: enabled,
                           icon: layer.icon,
                           showCheckmark: false,
                           labelLineLimit: 1) {
            switch layer.id {
            case "char":  store.charSuggest.toggle()
            case "emoji": store.emojiSuggest.toggle()
            default: break
            }
        }
        .draggable(layer.id)
    }

    // MARK: - Corpus card (radio-style single select, green)

    @ViewBuilder
    private func corpusCard(_ entry: CorpusEntry) -> some View {
        SelectableCardView(label: entry.label, desc: entry.desc,
                           selected: store.wordCorpus == entry.id,
                           icon: entry.icon,
                           showCheckmark: false,
                           labelLineLimit: 1) { store.wordCorpus = entry.id }
    }

    // MARK: - Domain grid (reuses DomainCardView)

    /// 詞庫網格＋拖放排序。量測掛 background 而非 GeometryReader 包裹——
    /// 後者在 ScrollView 裡會塌陷，導致內容與後續區塊重疊（舊疾）。
    private struct DomainDropGrid: View {
        @Bindable var store: PrefsStore
        let entries: Binding<[DomainEntry]>
        let color: Color
        let onReorder: () -> Void
        @State private var gridWidth: CGFloat = 0

        var body: some View {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
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
            .background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { gridWidth = g.size.width }
                        .onChange(of: g.size.width) { _, new in gridWidth = new }
                }
            }
            .dropDestination(for: String.self) { items, location in
                guard let draggedID = items.first else { return false }
                var arr = entries.wrappedValue
                guard let srcIdx = arr.firstIndex(where: { $0.id == draggedID }) else { return false }
                let item = arr.remove(at: srcIdx)
                let gridWidth = self.gridWidth
                let spacing: CGFloat = 8
                let minCell: CGFloat = 104
                let numCols = max(1, Int((gridWidth + spacing) / (minCell + spacing)))
                let cellWidth = (gridWidth - CGFloat(numCols - 1) * spacing) / CGFloat(numCols)
                let cellHeight: CGFloat = 100 + spacing
                let col = max(0, min(numCols - 1, Int(location.x / cellWidth)))
                let row = max(0, Int(location.y / cellHeight))
                let destIdx = min(arr.count, row * numCols + col)
                arr.insert(item, at: destIdx)
                entries.wrappedValue = arr
                onReorder()
                return true
            }
        }
    }

    @ViewBuilder
    private func domainGrid(entries: Binding<[DomainEntry]>, color: Color) -> some View {
        DomainDropGrid(store: store, entries: entries, color: color, onReorder: { saveDomainOrder() })
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
                    .foregroundStyle(on ? Typo.accent : .secondary)
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
                    .fill(on ? Typo.accent.opacity(0.18) : Typo.cardOff)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(on ? Typo.accent.opacity(0.7) : Typo.strokeOff,
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
        var order: [String]
        switch strategy {
        case "domain": order = ["domain", "word", "char"]
        case "char":   order = ["char", "word", "domain"]
        default:       order = ["word", "domain", "char"]
        }
        order.insert("emoji", at: store.emojiFirst ? 0 : order.count)
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
        // Emoji 只有「最前／其餘」兩種位置：非首位一律視為文字聯想優先
        store.emojiFirst = ids.first == "emoji"
        switch ids.first(where: { $0 != "emoji" }) {
        case "domain": store.suggestStrategy = "domain"
        case "char":   store.suggestStrategy = "char"
        default:       store.suggestStrategy = "general"
        }
    }

    private func saveDomainOrder() {
        store.domainOrder = (generalOrder + proOrder).map(\.id)
    }

    private func resetDefaults() {
        store.suggestStrategy = "general"
        store.wordCorpus = "wiki"
        store.charSuggest = true
        store.emojiSuggest = true
        store.emojiFirst = true
        store.regionVariant = "tw"
        loadOrder()
        generalOrder = DomainData.generalDomains
        proOrder = DomainData.proDomains
    }

    @ViewBuilder
    private func regionCard(_ id: String, label: String, icon: String, desc: String) -> some View {
        SelectableCardView(label: label, desc: desc,
                           selected: store.regionVariant == id,
                           iconText: icon,
                           showCheckmark: false,
                           highlightText: true,
                           labelLineLimit: 1) { store.regionVariant = id }
    }
}
#endif
