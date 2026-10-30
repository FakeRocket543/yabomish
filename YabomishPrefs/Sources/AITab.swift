import SwiftUI

/// AI 分頁：,,AI/,,PR 的後端設定。
///
/// 兩種模式——
///   CLI  ：spawn aiCommand（預設 /usr/bin/fm respond，Apple Intelligence 本機、
///          無 key、無網路）；可用 ollama/llama.cpp/claude 等 CLI 替換。
///   HTTP ：OpenAI Chat Completions 相容端點（provider 下拉從 models.dev
///          catalog 帶 base URL 與模型清單；自訂端點填 base_url 即可，
///          例如 `fm serve --port 11434` → http://127.0.0.1:11434/v1）。
///
/// preset 區塊直接編輯 commands.json 的 type:"preset" 條目——
/// preset key 本身就是指令（,,IG、,,FY），name 是選單顯示名，
/// prompt 支援 {clip}（剪貼簿全文）與 {input}（碼後補打字）。
/// 存檔後 postChange → IM 端 debounce 重讀 commands.json，即時生效。
struct AITab: View {
    @Bindable var store: PrefsStore

    // models.dev catalog（與 pi/hermes 同源）。dict key 才是 id——
    // entry 內沒有 id 欄位，只有 name/api/env/npm/doc/models。
    private struct Provider: Identifiable {
        let id: String
        let name: String
        let api: String?
        let doc: String?
        let modelIDs: [String]
    }
    /// 直接 decode dict：key→id，值→name/api/doc/models
    private struct ProviderDTO: Decodable {
        let name: String
        let api: String?
        let doc: String?
        let models: [String: ModelMeta]?
        struct ModelMeta: Decodable { let name: String? }
    }
    @State private var catalog: [Provider] = []
    @State private var catalogError: String? = nil
    @State private var providerID: String = "custom"   // "custom" = 手填
    @State private var presetRows: [PresetRow] = []
    @State private var presetDirty = false
    @State private var presetStatus = ""

    private struct PresetRow: Identifiable {
        var id = UUID()
        var key = ""
        var name = ""
        var prompt = ""
    }

    var body: some View {
        SettingsPage {
            // ── 模式 ──
            SettingsSection(title: "AI 來源", footnote: ",,AI 浮動窗與 preset 走同一個來源；切換即時生效。") {
                SegmentedRow("模式", selection: $store.aiMode,
                             options: [("cli", "CLI 指令"), ("http", "HTTP Provider")])
            }

            if store.aiMode == "cli" { cliSection } else { httpSection }

            // ── Preset ──
            SectionDivider()
            presetSection
        }
        .onAppear { loadPresets(); fetchCatalog() }
    }

    // MARK: - CLI section

    private var cliSection: some View {
        SettingsSection(title: "CLI 指令樣板",
                        footnote: "argv 以空白切：第一欄可執行檔；{prompt} 整欄替換、{clip} 代剪貼簿；沒寫 {prompt} 會自動加在最後一欄。") {
            VStack(alignment: .leading, spacing: 6) {
                TextField("argv 樣板", text: $store.aiCommand)
                    .textFieldStyle(.roundedBorder)
                Text("預設 /usr/bin/fm respond {prompt}（macOS 27+ Apple Intelligence）。\n例：/usr/local/bin/ollama run llama3 {prompt}、/usr/local/bin/claude -p {prompt}")
                    .font(Typo.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    // MARK: - HTTP section

    private var httpSection: some View {
        Group {
            SettingsSection(title: "Provider",
                            footnote: providerFootnote) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Provider", selection: $providerID) {
                        Text("自訂").tag("custom")
                        ForEach(catalog) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                    .onChange(of: providerID) { _, id in
                        guard let p = catalog.first(where: { $0.id == id }) else { return }
                        if let api = p.api { store.aiBaseURL = api }
                        if let first = p.modelIDs.first {
                            store.aiModel = first
                        }
                    }
                    if let p = catalog.first(where: { $0.id == providerID }),
                       let doc = p.doc, let url = URL(string: doc) {
                        Link("Provider 文件 / 申請 API key", destination: url)
                            .font(Typo.caption).padding(.horizontal, 12)
                    }
                    if let err = catalogError {
                        Text("catalog 下載失敗：\(err)").font(Typo.caption).foregroundStyle(Typo.warning)
                            .padding(.horizontal, 12)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }

            SettingsSection(title: "連線") {
                VStack(spacing: 8) {
                    labeledField("Base URL", text: $store.aiBaseURL,
                                 placeholder: "http://127.0.0.1:11434/v1")
                    labeledField("Model", text: $store.aiModel,
                                 placeholder: modelPlaceholder)
                    SecureField("API key（存本機 plist，遮蔽顯示）", text: $store.aiAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 12)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var providerFootnote: String {
        "聊天模型端點（OpenAI Chat Completions 相容）。本機 ollama/lmstudio/`fm serve` 都是這個形狀；填 base_url 即可。"
    }

    private var modelPlaceholder: String {
        if let p = catalog.first(where: { $0.id == providerID }),
           !p.modelIDs.isEmpty {
            return "例：\(p.modelIDs.prefix(3).joined(separator: "、"))"
        }
        return "模型名（部分端點可留空）"
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Typo.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal, 12)
    }

    private func fetchCatalog() {
        guard catalog.isEmpty else { return }
        let url = URL(string: "https://models.dev/api.json")!
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                if let error { catalogError = error.localizedDescription; return }
                guard let data,
                      let dict = try? JSONDecoder().decode([String: ProviderDTO].self, from: data)
                else { catalogError = "解碼失敗"; return }
                // dict key 才是 provider id——entry 內沒有 id 欄位
                catalog = dict.map { k, v in
                    Provider(id: k, name: v.name, api: v.api, doc: v.doc,
                             modelIDs: v.models?.keys.sorted() ?? [])
                }.sorted { $0.name < $1.name }
            }
        }.resume()
    }

    // MARK: - Preset section

    private var presetSection: some View {
        SettingsSection(title: "Preset（,,IG、,,FY 這種自訂碼）",
                        footnote: "preset key 本身就是指令（,,IG、,,IG補打）；,,PR 開選單瀏覽。{clip}=剪貼簿、{input}=碼後字。命名避開內建指令（zh/p/v/ai…）否則被內建吃掉。") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach($presetRows) { $row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            TextField("碼（如 ig）", text: $row.key)
                                .textFieldStyle(.roundedBorder).frame(width: 90)
                            TextField("名稱", text: $row.name)
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                presetRows.removeAll { $0.id == row.id }; presetDirty = true
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                        }
                        TextField("prompt 樣板（{clip}/{input}）", text: $row.prompt, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3)
                    }
                    .onChange(of: row.prompt) { presetDirty = true }
                    .onChange(of: row.key) { presetDirty = true }
                    .onChange(of: row.name) { presetDirty = true }
                    if row.id != presetRows.last?.id { Divider() }
                }
                HStack {
                    Button {
                        presetRows.append(PresetRow()); presetDirty = true
                    } label: { Label("新增 preset", systemImage: "plus") }
                    Spacer()
                    Text(presetStatus).font(Typo.caption).foregroundStyle(.secondary)
                    Button("儲存") { savePresets() }.disabled(!presetDirty)
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
            .padding(.top, 4)
        }
    }

    private var commandsPath: String {
        NSHomeDirectory() + "/Library/Application Support/\(store.dataDirName)/commands.json"
    }

    private func loadPresets() {
        guard let data = FileManager.default.contents(atPath: commandsPath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else { presetRows = []; return }
        presetRows = dict.compactMap { k, v in
            guard v["type"] as? String == "preset" else { return nil }
            return PresetRow(key: k,
                             name: v["name"] as? String ?? k,
                             prompt: v["prompt"] as? String ?? "")
        }.sorted { $0.key < $1.key }
        presetDirty = false
    }

    private func savePresets() {
        var dict: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: commandsPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = existing
        }
        // 移除全部 preset 條目後重寫（其他 type 保留）
        for (k, v) in dict {
            if (v as? [String: Any])?["type"] as? String == "preset" { dict.removeValue(forKey: k) }
        }
        for row in presetRows where !row.key.isEmpty && !row.prompt.isEmpty {
            dict[row.key] = ["type": "preset", "name": row.name, "prompt": row.prompt]
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
            (try? data.write(to: URL(fileURLWithPath: commandsPath), options: .atomic)) != nil
        else { presetStatus = "寫入失敗"; return }
        presetDirty = false
        presetStatus = "已儲存 — IM 端自動重讀"
        store.postChange()
    }
}
