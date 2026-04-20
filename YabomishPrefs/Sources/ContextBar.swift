import SwiftUI

struct ContextBar: View {
    @Bindable var store: PrefsStore
    @State private var profiles: [ContextProfile] = []
    @State private var showAdd = false
    @State private var deleteTarget: ContextProfile?
    @State private var editTarget: ContextProfile?
    @State private var importAlert: String?

    // New profile form
    @State private var newName = ""
    @State private var newCode = ""
    @State private var newIcon = "💬"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(profiles) { p in
                        Button {
                            applyProfile(p)
                        } label: {
                            HStack(spacing: 4) {
                                Text(p.icon)
                                Text(p.name).font(Typo.caption)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(store.currentContext == p.code ? Typo.cyan.opacity(0.25) : Color.primary.opacity(0.06))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(store.currentContext == p.code ? Typo.cyan : Color.clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("編輯⋯") { editTarget = p }
                            Button("複製⋯") { copyProfile(p) }
                            Divider()
                            Button("刪除「\(p.name)」", role: .destructive) { deleteTarget = p }
                        }
                    }
                    if profiles.count < ContextProfile.maxProfiles {
                        Button { showAdd = true } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "plus").font(.caption)
                                Text("新增").font(Typo.caption)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 12) {
                Text(",,X + 碼切換").font(Typo.caption).foregroundStyle(.secondary)
                Spacer()
                Button("重置") { resetContext() }.font(Typo.caption)
                Button("匯入⋯") { importProfile() }.font(Typo.caption)
                Button("匯出⋯") { exportProfile() }.font(Typo.caption)
                    .disabled(store.currentContext == nil)
            }
        }
        .onAppear { reload() }
        .alert("確定刪除「\(deleteTarget?.name ?? "")」？", isPresented: Binding(
            get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("刪除", role: .destructive) {
                if let t = deleteTarget {
                    t.delete()
                    if store.currentContext == t.code { store.currentContext = nil }
                    reload()
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("匯入結果", isPresented: Binding(
            get: { importAlert != nil }, set: { if !$0 { importAlert = nil } }
        )) { Button("好") {} } message: { Text(importAlert ?? "") }
        .sheet(isPresented: $showAdd) { addSheet }
        .sheet(item: $editTarget) { p in
            ContextProfileEditor(profile: p, isActive: store.currentContext == p.code) { updated in
                if store.currentContext == updated.code { applyProfile(updated) }
                reload()
            }
        }
    }

    private var addSheet: some View {
        VStack(spacing: 12) {
            Text("新增語境").font(Typo.h2)
            HStack {
                Text("Icon").frame(width: 60, alignment: .leading)
                TextField("emoji", text: $newIcon).textFieldStyle(.roundedBorder).frame(width: 60)
            }
            HStack {
                Text("名稱").frame(width: 60, alignment: .leading)
                TextField("如：工作模式", text: $newName).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("命令碼").frame(width: 60, alignment: .leading)
                TextField("2 字母", text: $newCode).textFieldStyle(.roundedBorder).frame(width: 80)
                    .font(Typo.bodyMono)
                Text("→ ,,X\(newCode.uppercased())").font(Typo.caption).foregroundStyle(.secondary)
            }
            if let err = validateNew() {
                Text(err).font(Typo.caption).foregroundStyle(Typo.warn)
            }
            HStack {
                Button("取消") { showAdd = false }
                Spacer()
                Button("建立") {
                    var p = ContextProfile.snapshotCurrent(name: newName, icon: newIcon, code: newCode.lowercased())
                    p.inputMode = "t"
                    p.save()
                    showAdd = false; newName = ""; newCode = ""; newIcon = "💬"
                    reload()
                }
                .disabled(validateNew() != nil)
            }
        }
        .padding(20).frame(width: 320)
    }

    private func validateNew() -> String? {
        let c = newCode.lowercased()
        if newName.isEmpty { return "請輸入名稱" }
        if c.count != 2 { return "命令碼需 2 字母" }
        if ContextProfile.reservedCodes.contains(c) { return "此碼為系統保留" }
        if profiles.contains(where: { $0.code == c }) { return "此碼已被使用" }
        return nil
    }

    private func applyProfile(_ p: ContextProfile) {
        store.suggestEnabled = p.suggestEnabled
        store.suggestStrategy = p.suggestStrategy
        store.charSuggest = p.charSuggest
        store.wordCorpus = p.wordCorpus
        store.regionVariant = p.regionVariant
        store.fuzzyMatch = p.fuzzyMatch
        store.autoCommit = p.autoCommit
        store.domainOrder = p.domainOrder
        for d in DomainData.allDomains { store.setDomainEnabled(d.id, false) }
        for (key, val) in p.domainEnabled { store.setDomainEnabled(key, val) }
        store.currentContext = p.code
    }

    private func resetContext() {
        if let p = ContextProfile.load(code: "df") { applyProfile(p) }
        else { store.currentContext = nil }
    }

    private func copyProfile(_ p: ContextProfile) {
        guard profiles.count < ContextProfile.maxProfiles else { return }
        newName = p.name + " 副本"
        newIcon = p.icon
        newCode = ""
        showAdd = true
    }

    private func reload() {
        ContextProfile.createDefaults()
        profiles = ContextProfile.loadAll().sorted {
            let order = ["df", "tw", "ch", "tc"]
            let a = order.firstIndex(of: $0.code) ?? Int.max
            let b = order.firstIndex(of: $1.code) ?? Int.max
            return a == b ? $0.code < $1.code : a < b
        }
    }

    private func exportProfile() {
        guard let code = store.currentContext, let p = ContextProfile.load(code: code),
              let data = try? JSONEncoder().encode(p) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "yabomish_語境_\(p.name).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let p = try? JSONDecoder().decode(ContextProfile.self, from: data) else { return }
        if profiles.contains(where: { $0.code == p.code }) {
            importAlert = "命令碼「\(p.code)」已存在，請先刪除再匯入"; return
        }
        if profiles.count >= ContextProfile.maxProfiles {
            importAlert = "已達上限 \(ContextProfile.maxProfiles) 組"; return
        }
        p.save(); reload()
        importAlert = "已匯入「\(p.icon) \(p.name)」"
    }
}
