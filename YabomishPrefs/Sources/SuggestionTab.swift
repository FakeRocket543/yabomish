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

/// 聯想頁：開關、語境切換、層順序、語料來源、用詞習慣。
/// 詞庫清單已獨立為「一般詞庫」「專業詞庫」兩頁。
struct SuggestionTab: View {
    @Bindable var store: PrefsStore
    @State private var layerOrder: [SuggestLayer] = []
    @State private var showResetConfirm = false

    var body: some View {
        SettingsPage {
            SettingsSection(title: "聯想輸入") {
                ToggleRow(label: "聯想輸入", icon: "lightbulb",
                          desc: "送字後推薦候選",
                          on: $store.suggestEnabled)
                InsetDivider()
                ToggleRow(label: "聯想預先反白", icon: "highlighter",
                          desc: "反白聯想列第一個候選（預設關）",
                          on: $store.suggestPreselect)
            }

            SettingsSection(title: "語境切換",
                            footnote: "點擊切換 ｜ 右鍵或 ⋯ 編輯或複製 ｜ 輸入法中 ,,X + 碼 切換（如 ,,XTW）。,,XRS 重置為預設 ｜ ,,XS 儲存當前設定 ｜ ,,XI 顯示當前語境") {
                ContextBar(store: store)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }

            SettingsSection(title: "聯想層順序",
                            footnote: "上下拖放調整優先順序；Emoji 排最前時一定看得到，排其餘位置則文字聯想優先、聯想列有空位才顯示。") {
                ForEach(Array(layerOrder.enumerated()), id: \.element.id) { i, layer in
                    if i > 0 { InsetDivider() }
                    layerRow(layer, index: i)
                }
            }

            SettingsSection(title: "詞級語料來源") {
                ChoiceRow(label: "萌典", icon: "character.book.closed",
                          desc: "教育部詞組",
                          selected: store.wordCorpus == "moedict") { store.wordCorpus = "moedict" }
                InsetDivider()
                ChoiceRow(label: "維基", icon: "globe.asia.australia",
                          desc: "維基百科斷詞",
                          selected: store.wordCorpus == "wiki") { store.wordCorpus = "wiki" }
                InsetDivider()
                ChoiceRow(label: "新聞", icon: "newspaper",
                          desc: "台灣新聞斷詞",
                          selected: store.wordCorpus == "news") { store.wordCorpus = "news" }
            }

            SettingsSection(title: "用詞習慣",
                            footnote: "影響候選排序權重，偏向所選地區的慣用詞。") {
                SegmentedRow("地區", selection: $store.regionVariant,
                             options: [("tw", "臺灣用詞"), ("cn", "中式用詞")])
            }

            HStack {
                Button("重置聯想設定⋯") { showResetConfirm = true }
                Spacer()
            }
        }
        .onAppear { loadOrder() }
        // #39：IM 端（,,SG／,,X）改設定時重讀排序；讀 generation 讓通知能驅動重繪
        .onChange(of: store.generation) { _, _ in loadOrder() }
        .alert("確定重置聯想設定？", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) { resetDefaults() }
        }
    }

    // MARK: - Layer row (drag-reorderable)

    @ViewBuilder
    private func layerRow(_ layer: SuggestLayer, index: Int) -> some View {
        let canToggle = layer.id == "char" || layer.id == "emoji"
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: layer.icon)
                .font(.system(size: 15))
                .foregroundStyle(Typo.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(layer.label).font(Typo.body)
                Text(layer.desc).font(Typo.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(index + 1)")
                .font(Typo.cardBadge)
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .trailing)
            if canToggle {
                Toggle("", isOn: layer.id == "char" ? $store.charSuggest : $store.emojiSuggest)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .draggable(layer.id)
        .dropDestination(for: String.self) { items, location in
            guard let draggedID = items.first,
                  let src = layerOrder.firstIndex(where: { $0.id == draggedID }),
                  src != index else { return false }
            // 落點在列上半 → 插到該列前；下半 → 插到該列後
            let dest = location.y > 18 ? index + 1 : index
            let item = layerOrder.remove(at: src)
            layerOrder.insert(item, at: min(layerOrder.count, dest > src ? dest - 1 : dest))
            saveStrategy()
            return true
        }
        .contextMenu {
            Button("上移") { moveLayer(layer.id, by: -1) }
            Button("下移") { moveLayer(layer.id, by: 1) }
        }
        .accessibilityAction(named: "上移") { moveLayer(layer.id, by: -1) }
        .accessibilityAction(named: "下移") { moveLayer(layer.id, by: 1) }
    }

    /// 鍵盤／VoiceOver 移動聯想層（拖放的等價路徑）
    private func moveLayer(_ id: String, by delta: Int) {
        guard let src = layerOrder.firstIndex(where: { $0.id == id }) else { return }
        let dest = min(layerOrder.count - 1, max(0, src + delta))
        guard dest != src else { return }
        layerOrder.move(fromOffsets: IndexSet(integer: src), toOffset: dest > src ? dest + 1 : dest)
        saveStrategy()
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

    private func resetDefaults() {
        store.suggestStrategy = "general"
        store.wordCorpus = "wiki"
        store.charSuggest = true
        store.emojiSuggest = true
        store.emojiFirst = true
        store.regionVariant = "tw"
        // #28：重置也要寫回 defaults — [] 即 catalog 預設序（詞庫頁載入時以 catalog 為準）
        store.domainOrder = []
        loadOrder()
    }
}
#endif
