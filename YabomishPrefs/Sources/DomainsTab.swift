#if !MINIMAL
import SwiftUI

/// 詞庫排序讀寫（domainOrder 為單一清單、一般與專業交錯——兩頁各自
/// 改自己那半，寫回時保留另一半）。
enum DomainOrderHelper {
    static func load(store: PrefsStore) -> (general: [DomainEntry], pro: [DomainEntry]) {
        let saved = store.domainOrder
        guard !saved.isEmpty else {
            return (DomainData.generalDomains, DomainData.proDomains)
        }
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
        return (gen, pro)
    }

    static func save(general: [DomainEntry], pro: [DomainEntry], store: PrefsStore) {
        store.domainOrder = (general + pro).map(\.id)
    }

    static func formatCount(_ n: Int) -> String? {
        guard n > 0 else { return nil }
        if n >= 10000 { return String(format: "%.1f 萬", Double(n) / 10000.0) }
        return "\(n) 筆"
    }
}

/// 詞庫列：icon＋標題＋說明＋條數徽章＋開關，支援拖放調整優先順序。
private struct DomainRow: View {
    @Bindable var store: PrefsStore
    let entry: DomainEntry
    let onDrop: (String) -> Void

    var body: some View {
        ToggleRow(label: entry.label, icon: entry.icon, desc: entry.desc,
                  badge: DomainOrderHelper.formatCount(DomainData.binEntryCount(file: entry.file)),
                  on: Binding(
                      get: { store.domainEnabled(entry.id) },
                      set: { store.setDomainEnabled(entry.id, $0) }
                  ))
        .draggable(entry.id)
        .dropDestination(for: String.self) { items, _ in
            guard let draggedID = items.first else { return false }
            onDrop(draggedID)
            return true
        }
    }
}

/// 一般詞庫頁：12 個一般領域詞庫的啟用＋排序，附即時搜尋。
struct GeneralDomainsTab: View {
    @Bindable var store: PrefsStore
    @State private var generalOrder: [DomainEntry]
    @State private var proOrder: [DomainEntry]
    @State private var query = ""

    init(store: PrefsStore) {
        self.store = store
        let (g, p) = DomainOrderHelper.load(store: store)
        _generalOrder = State(initialValue: g)
        _proOrder = State(initialValue: p)
    }

    private var visible: [DomainEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return generalOrder }
        return generalOrder.filter {
            $0.label.localizedCaseInsensitiveContains(q) || $0.desc.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        SettingsPage {
            // toolbar 已移除（main.swift w.toolbar=nil），頁首內容不會再被半透明材質蓋住
            HStack {
                SettingsHeader("一般詞庫")
                Spacer()
                TextField("搜尋詞庫", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }
            SettingsGroupBox {
                ForEach(Array(visible.enumerated()), id: \.element.id) { i, entry in
                    if i > 0 { InsetDivider() }
                    DomainRow(store: store, entry: entry) { draggedID in
                        // 搜尋中僅允許啟停（過濾快照非完整順序，拖放停用）
                        guard query.isEmpty,
                              let src = generalOrder.firstIndex(where: { $0.id == draggedID }),
                              let dst = generalOrder.firstIndex(where: { $0.id == entry.id }),
                              src != dst else { return }
                        generalOrder.move(fromOffsets: IndexSet(integer: src),
                                          toOffset: dst > src ? dst + 1 : dst)
                        DomainOrderHelper.save(general: generalOrder, pro: proOrder, store: store)
                    }
                }
            }
            SettingsFootnote("開關控制是否參與聯想；上下拖放調整優先順序（越上面越優先）。搜尋時拖放停用。")
        }
        .onChange(of: store.generation) { _, _ in
            (generalOrder, proOrder) = DomainOrderHelper.load(store: store)
        }
    }
}

/// 專業詞庫頁：28 個樂詞網＋維基專業詞典，按類別分組。
struct ProDomainsTab: View {
    @Bindable var store: PrefsStore
    @State private var generalOrder: [DomainEntry]
    @State private var proOrder: [DomainEntry]

    init(store: PrefsStore) {
        self.store = store
        let (g, p) = DomainOrderHelper.load(store: store)
        _generalOrder = State(initialValue: g)
        _proOrder = State(initialValue: p)
    }

    private var grouped: [DomainCategory: [DomainEntry]] {
        Dictionary(grouping: proOrder, by: \.category)
    }

    var body: some View {
        SettingsPage {
            ForEach(DomainData.proCategoryOrder, id: \.self) { cat in
                if let items = grouped[cat], !items.isEmpty {
                    SettingsSection(title: DomainData.categoryLabel(cat),
                                    footnote: cat == DomainData.proCategoryOrder.first
                                        ? "點擊啟用／停用。上下拖放調整建議優先順序。"
                                        : nil) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, entry in
                            if i > 0 { InsetDivider() }
                            DomainRow(store: store, entry: entry) { draggedID in
                                guard let src = proOrder.firstIndex(where: { $0.id == draggedID }),
                                      let dst = proOrder.firstIndex(where: { $0.id == entry.id }),
                                      src != dst else { return }
                                proOrder.move(fromOffsets: IndexSet(integer: src),
                                              toOffset: dst > src ? dst + 1 : dst)
                                DomainOrderHelper.save(general: generalOrder, pro: proOrder, store: store)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: store.generation) { _, _ in
            (generalOrder, proOrder) = DomainOrderHelper.load(store: store)
        }
    }
}
#endif
