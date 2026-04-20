import SwiftUI
import UniformTypeIdentifiers

private extension Data {
    func u32(_ offset: Int) -> UInt32 {
        withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
    }
    func u16(_ offset: Int) -> UInt16 {
        withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self) }
    }
}

struct ShortcutTab: View {
    @State private var code = ""
    @State private var content = ""
    @State private var shortcuts: [(code: String, content: String)] = []
    @State private var search = ""
    @State private var codeStatus: CodeStatus = .empty
    @State private var freeCount = 0
    @State private var corpusQuery = ""
    @State private var corpusResults: [CorpusHit] = []
    @State private var importAlert: String?

    enum CodeStatus {
        case empty, tooShort, tooLong, available
        case existsInCIN(String), existsInShortcuts(String)
    }

    private static var cinCodes: Set<String>?
    private static let dir: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Yabomish/tables").path + "/"
    }()
    private static let filePath = dir + "user_shortcuts.txt"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── 詞庫查詢 ──
                Label("詞庫查詢", systemImage: "magnifyingglass").font(Typo.h2)
                corpusSearchSection

                // ── 快捷碼說明 ──
                SectionDivider()
                Label("快捷碼", systemImage: "bolt.fill").font(Typo.h2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("把空碼變成你的快捷碼 — 打 2–4 碼直接輸出整段文字。")
                        .font(Typo.hint)
                    Text("適合綁定 agent 指令、prompt template、常用片語、簽名檔。")
                        .font(Typo.hint).foregroundStyle(.secondary)
                }

                // Demo examples
                SectionDivider()
                Label("範例", systemImage: "lightbulb").font(Typo.h2)
                VStack(alignment: .leading, spacing: 4) {
                        demoRow("agpt", "請用繁體中文回答，並附上參考來源")
                        demoRow("amtg", "@channel 今天的 standup 更新如下：")
                        demoRow("acmd", "cd ~/Projects && git status")
                        demoRow("asig", "Best regards, — your name")
                    }

                // ── 新增 ──
                SectionDivider()
                Label("新增快捷碼", systemImage: "plus.circle").font(Typo.h2)
                addSection

                // ── 列表 ──
                SectionDivider()
                Label("已建立", systemImage: "list.bullet").font(Typo.h2)
                listSection

                Text("檔案路徑：~/Library/Application Support/Yabomish/tables/user_shortcuts.txt\n# 開頭為註解，可用來分類。修改後輸入 ,,RL + 空白鍵 即時重載。")
                    .font(Typo.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .onAppear {
            loadShortcuts()
            countFreeCodes()
        }
        .alert("匯入結果", isPresented: Binding(get: { importAlert != nil }, set: { if !$0 { importAlert = nil } })) {
            Button("好") { importAlert = nil }
        } message: {
            Text(importAlert ?? "")
        }
    }

    // MARK: - Add Section

    @ViewBuilder
    private func demoRow(_ code: String, _ content: String) -> some View {
        HStack(spacing: 8) {
            Text(code).font(Typo.bodyMono)
                .frame(width: 50, alignment: .leading)
            Text("→").foregroundStyle(.tertiary).font(Typo.cardDesc)
            Text(content).font(Typo.body).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("編碼")
                TextField("2–4 碼", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .font(Typo.bodyMono)
                    .onChange(of: code) { validateCode() }
                statusView
            }
            Text("內容")
            TextEditor(text: $content)
                .font(.body)
                .frame(height: 60)
                .border(Typo.strokeOff)
            HStack {
                Spacer()
                Button("＋ 新增") { addShortcut() }
                    .disabled(code.count < 2 || code.count > 4 || content.isEmpty)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch codeStatus {
        case .empty: EmptyView()
        case .tooShort: Text("至少 2 碼").foregroundStyle(.secondary).font(Typo.caption)
        case .tooLong: Text("最多 4 碼").foregroundStyle(.secondary).font(Typo.caption)
        case .available: Text("✓ 可用").foregroundStyle(Typo.ok).font(Typo.caption)
        case .existsInCIN(let s): Text("字表已有：\(s)").foregroundStyle(Typo.warn).font(Typo.caption)
        case .existsInShortcuts(let s): Text("已有快捷碼，將覆蓋：\(s)").foregroundStyle(Typo.warn).font(Typo.caption)
        }
    }

    // MARK: - List Section

    private var listSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜尋", text: $search)
                    .textFieldStyle(.roundedBorder)
                Spacer()
                Button("匯入⋯") { importShortcuts() }
                Button("匯出⋯") { exportShortcuts() }
            }
            List {
                ForEach(filtered, id: \.code) { sc in
                    HStack {
                        Text(sc.code)
                            .font(Typo.bodyMono)
                            .frame(width: 80, alignment: .leading)
                        Text(sc.content).lineLimit(1)
                        Spacer()
                        Button("✎") { code = sc.code; content = sc.content }
                            .buttonStyle(.borderless)
                        Button("🗑") { deleteShortcut(code: sc.code) }
                            .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { code = sc.code; content = sc.content }
                }
            }
            .frame(minHeight: 200)
            HStack {
                Text("\(shortcuts.count) 筆快捷碼")
                Spacer()
                Text("4碼空碼剩餘 \(freeCount)")
            }
            .font(Typo.caption).foregroundStyle(.secondary)
        }
    }

    private var filtered: [(code: String, content: String)] {
        guard !search.isEmpty else { return shortcuts }
        let q = search.lowercased()
        return shortcuts.filter { $0.code.lowercased().contains(q) || $0.content.contains(q) }
    }

    // MARK: - Data

    private func loadShortcuts() {
        // Migrate from old path if needed
        let oldPath = NSHomeDirectory() + "/Library/YabomishIM/tables/user_shortcuts.txt"
        if !FileManager.default.fileExists(atPath: Self.filePath),
           FileManager.default.fileExists(atPath: oldPath) {
            try? FileManager.default.createDirectory(atPath: Self.dir, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(atPath: oldPath, toPath: Self.filePath)
        }
        guard let text = try? String(contentsOfFile: Self.filePath, encoding: .utf8) else { return }
        shortcuts = text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("#") { return nil }
            let parts = s.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (code: String(parts[0]), content: String(parts[1]))
        }
    }

    private func saveShortcuts() {
        try? FileManager.default.createDirectory(atPath: Self.dir, withIntermediateDirectories: true)
        // Preserve comment lines from existing file
        var comments: [String] = []
        if let existing = try? String(contentsOfFile: Self.filePath, encoding: .utf8) {
            comments = existing.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { $0.hasPrefix("#") }
        }
        var lines = comments
        lines.append(contentsOf: shortcuts.map { "\($0.code)\t\($0.content)" })
        let text = lines.joined(separator: "\n")
        try? text.write(toFile: Self.filePath, atomically: true, encoding: .utf8)
        DistributedNotificationCenter.default().post(name: .init("com.yabomish.reloadTables"), object: nil)
    }

    private func addShortcut() {
        let c = code.lowercased().trimmingCharacters(in: .whitespaces)
        let v = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard c.count >= 2, !v.isEmpty else { return }
        if let idx = shortcuts.firstIndex(where: { $0.code == c }) {
            shortcuts[idx] = (code: c, content: v)
        } else {
            shortcuts.append((code: c, content: v))
        }
        saveShortcuts()
        code = ""
        content = ""
        codeStatus = .empty
        countFreeCodes()
    }

    private func deleteShortcut(code: String) {
        shortcuts.removeAll { $0.code == code }
        saveShortcuts()
        countFreeCodes()
    }

    private func validateCode() {
        let c = code.lowercased().trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { codeStatus = .empty; return }
        guard c.count >= 2 else { codeStatus = .tooShort; return }
        guard c.count <= 4 else { codeStatus = .tooLong; return }
        if let existing = shortcuts.first(where: { $0.code == c }) {
            codeStatus = .existsInShortcuts(existing.content)
            return
        }
        let cin = Self.getCINCodes()
        if cin.contains(c) {
            codeStatus = .existsInCIN(c)
        } else {
            codeStatus = .available
        }
    }

    private static func getCINCodes() -> Set<String> {
        if let cached = cinCodes { return cached }
        let codes = loadCINCodes()
        cinCodes = codes
        return codes
    }

    static func loadCINCodes() -> Set<String> {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Yabomish").path
        let paths = [
            appSupport + "/liu.bin",
            "/Library/Input Methods/YabomishIM.app/Contents/Resources/liu.bin",
            NSHomeDirectory() + "/Library/YabomishIM/liu.bin",
        ]
        guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              data.count >= 128,
              data[0] == 0x43, data[1] == 0x49, data[2] == 0x4E, data[3] == 0x4D
        else { return [] }
        let entryCount = Int(data.u32(4))
        let codesOff = Int(data.u32(96))
        let stringsOff = Int(data.u32(104))
        var codes = Set<String>()
        for i in 0..<entryCount {
            let eo = codesOff + i * 6
            guard eo + 6 <= data.count else { break }
            let so = stringsOff + Int(data.u32(eo))
            let sl = Int(data.u16(eo + 4))
            guard so + sl <= data.count else { continue }
            if let s = String(data: data[so..<so+sl], encoding: .ascii) {
                codes.insert(s.lowercased())
            }
        }
        return codes
    }

    private func countFreeCodes() {
        let total = 26 * 26 * 26 * 26 // 26^4
        let cinUsed = Self.getCINCodes().filter { $0.count == 4 }.count
        let scUsed = Set(shortcuts.map(\.code)).filter { $0.count == 4 }.count
        freeCount = max(0, total - cinUsed - scUsed)
    }

    // MARK: - Import / Export

    private func importShortcuts() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let incoming = text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line -> (String, String)? in
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("#") { return nil }
            let parts = s.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]).lowercased(), String(parts[1]))
        }
        let cin = Self.getCINCodes()
        var added = 0, updated = 0, skippedLen: [String] = [], skippedCIN: [String] = []
        for (c, v) in incoming {
            if c.count < 2 || c.count > 4 { skippedLen.append(c); continue }
            if cin.contains(c) { skippedCIN.append(c); continue }
            if let idx = shortcuts.firstIndex(where: { $0.code == c }) {
                shortcuts[idx] = (code: c, content: v); updated += 1
            } else {
                shortcuts.append((code: c, content: v)); added += 1
            }
        }
        saveShortcuts()
        countFreeCodes()
        // Build summary
        var msg = "新增 \(added) 筆、覆蓋 \(updated) 筆"
        if !skippedLen.isEmpty {
            msg += "\n略過（長度不符）：\(skippedLen.prefix(5).joined(separator: "、"))"
            if skippedLen.count > 5 { msg += " 等 \(skippedLen.count) 筆" }
        }
        if !skippedCIN.isEmpty {
            msg += "\n略過（字表衝突）：\(skippedCIN.prefix(5).joined(separator: "、"))"
            if skippedCIN.count > 5 { msg += " 等 \(skippedCIN.count) 筆" }
        }
        importAlert = msg
    }

    private func exportShortcuts() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "yabomish_快捷碼.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var lines = [
            "# Yabomish 快捷碼",
            "# 格式：編碼<Tab>內容（# 開頭為註解，可用來分類）",
            "#",
        ]
        lines.append(contentsOf: shortcuts.map { "\($0.code)\t\($0.content)" })
        let text = lines.joined(separator: "\n")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Corpus Search

    private var corpusSearchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("輸入中文詞查詢是否已收錄", text: $corpusQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { searchCorpus() }
                Button("查詢") { searchCorpus() }
                    .disabled(corpusQuery.count < 2)
            }
            if !corpusResults.isEmpty {
                let found = corpusResults.filter { !$0.words.isEmpty }
                if found.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle").foregroundStyle(.red)
                        Text("未在任何詞庫中找到「\(corpusQuery)」").font(Typo.body).foregroundStyle(.red)
                    }
                } else {
                    HStack {
                        Text("✓ 在 \(found.count) 個詞庫中找到").font(Typo.caption).foregroundStyle(Typo.ok)
                        Spacer()
                        Button("匯出 CSV⋯") { exportCorpusCSV(found) }
                            .font(Typo.caption)
                    }
                    // Table
                    VStack(spacing: 0) {
                        // Header
                        HStack(spacing: 0) {
                            Text("詞庫").font(Typo.caption).bold().frame(width: 120, alignment: .leading)
                            Text("匹配詞條").font(Typo.caption).bold().frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        Divider()
                        // Rows
                        ForEach(found, id: \.label) { item in
                            HStack(alignment: .top, spacing: 0) {
                                Text(item.label).font(Typo.caption).frame(width: 120, alignment: .leading).lineLimit(1)
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(item.words, id: \.self) { w in
                                        Text(w).font(Typo.body)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            Divider()
                        }
                    }
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1)))
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func exportCorpusCSV(_ hits: [CorpusHit]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "詞庫查詢_\(corpusQuery).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var csv = "詞庫,詞條\n"
        for hit in hits {
            for word in hit.words {
                csv += "\(hit.label),\(word)\n"
            }
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private struct CorpusHit: Equatable {
        let label: String
        let words: [String]
    }

    private func searchCorpus() {
        let q = corpusQuery.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return }
        var results: [CorpusHit] = []

        let resDir = "/Library/Input Methods/YabomishIM.app/Contents/Resources"
        let bins: [(String, String)] = DomainData.allDomains.map { ($0.file, $0.label) } + [
            ("chengyu", "成語"), ("phrases", "萌典詞組"), ("ner_phrases", "NER 詞組"),
            ("word_ngram", "維基詞頻"), ("word_news", "新聞詞頻"), ("yoji", "日本熟語"),
        ]
        for (file, label) in bins {
            let path = resDir + "/\(file).bin"
            let words = wbmmMatch(path: path, query: q)
            if !words.isEmpty {
                results.append(CorpusHit(label: label, words: words))
            }
        }

        if shortcuts.contains(where: { $0.content.contains(q) || $0.code == q }) {
            let matched = shortcuts.filter { $0.content.contains(q) }.map(\.content)
            results.append(CorpusHit(label: "使用者快捷碼", words: matched.isEmpty ? [q] : Array(matched.prefix(5))))
        }

        if results.isEmpty {
            results.append(CorpusHit(label: "", words: []))
        }
        corpusResults = results
    }

    /// Return matched words from a WBMM bin for the given query.
    /// All bins use suffix format: key + value = full word.
    private func wbmmMatch(path: String, query: String) -> [String] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              data.count >= 16, data[0] == 0x57, data[1] == 0x42, data[2] == 0x4D, data[3] == 0x4D
        else { return [] }
        let kc = Int(data.u32(4))
        let ki = Int(data.u32(8))
        let vi = Int(data.u32(12))
        var found = Set<String>()

        for plen in 1...query.count {
            let prefix = String(query.prefix(plen))
            let prefixBytes = Array(prefix.utf8)
            var lo = 0, hi = kc - 1
            while lo <= hi {
                let mid = (lo + hi) / 2
                let eo = ki + mid * 12
                guard eo + 12 <= data.count else { break }
                let so = Int(data.u32(eo))
                let sl = Int(data.u16(eo + 4))
                guard so + sl <= data.count else { break }
                let key = Array(data[so..<(so + sl)])
                if key == prefixBytes {
                    let vs = Int(data.u32(eo + 6))
                    let vc = Int(data.u16(eo + 10))
                    for j in 0..<vc {
                        let vo = vi + (vs + j) * 6
                        guard vo + 6 <= data.count else { break }
                        let vso = Int(data.u32(vo))
                        let vsl = Int(data.u16(vo + 4))
                        guard vso + vsl <= data.count else { continue }
                        if let v = String(data: data[vso..<(vso + vsl)], encoding: .utf8) {
                            let full = prefix + v
                            if full.hasPrefix(query) { found.insert(full) }
                        }
                    }
                    break
                }
                if key.lexicographicallyPrecedes(prefixBytes) { lo = mid + 1 } else { hi = mid - 1 }
            }
            if found.count >= 8 { break }
        }
        return Array(found.sorted().prefix(8))
    }
}
