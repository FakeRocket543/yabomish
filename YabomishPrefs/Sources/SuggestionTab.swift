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

struct SuggestionTab: View {
    @Bindable var store: PrefsStore
    @State private var layerOrder: [SuggestLayer] = []
    @State private var saved = false
    @State private var showResetConfirm = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("拖拉卡片調整聯想優先順序。點擊啟用／停用。")
                    .font(.callout).foregroundStyle(.secondary)

                Label("聯想層", systemImage: "square.3.layers.3d").font(.headline)

                LazyVGrid(columns: columns, spacing: 8) {
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

                // Word corpus sub-picker
                GroupBox("詞級語料來源") {
                    Picker("語料", selection: $store.wordCorpus) {
                        Text("萌典詞組").tag("moedict")
                        Text("維基斷詞").tag("wiki")
                        Text("台灣新聞斷詞").tag("news")
                    }
                    .padding(.vertical, 4)
                }

                HStack {
                    Button("重置") { showResetConfirm = true }
                    Spacer()
                    if saved { Text("已套用 ✓").foregroundStyle(.green).transition(.opacity) }
                    Button("套用") { apply() }.controlSize(.large)
                }
            }
            .padding(20)
        }
        .onAppear { loadOrder() }
        .alert("確定重置聯想設定？", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) { resetDefaults() }
        }
    }

    @ViewBuilder
    private func layerCard(_ layer: SuggestLayer) -> some View {
        let enabled = isEnabled(layer.id)
        Button { toggleEnabled(layer.id) } label: {
            VStack(spacing: 6) {
                Image(systemName: layer.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(enabled ? Color.accentColor : .secondary)
                Text(layer.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(layer.desc)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(enabled ? Color.accentColor.opacity(0.12) : Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(enabled ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor),
                            lineWidth: enabled ? 1.5 : 0.5)
            )
            .opacity(enabled ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .draggable(layer.id)
    }

    // MARK: - State

    private func isEnabled(_ id: String) -> Bool {
        switch id {
        case "char": return store.charSuggest
        default: return true // word and domain always on (order matters, not toggle)
        }
    }

    private func toggleEnabled(_ id: String) {
        if id == "char" { store.charSuggest.toggle() }
    }

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

    private func apply() {
        let ids = layerOrder.map(\.id)
        if ids.first == "domain" { store.suggestStrategy = "domain" }
        else if ids.first == "char" { store.suggestStrategy = "char" }
        else { store.suggestStrategy = "general" }
        store.postChange()
        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { saved = false } }
    }

    private func resetDefaults() {
        store.suggestStrategy = "general"
        store.wordCorpus = "wiki"
        store.charSuggest = true
        loadOrder()
    }
}
