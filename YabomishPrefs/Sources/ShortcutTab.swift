import SwiftUI

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

    enum CodeStatus {
        case empty, tooShort, available
        case existsInCIN(String), existsInShortcuts(String)
    }

    private static var cinCodes: Set<String>?
    private static let dir = NSHomeDirectory() + "/Library/YabomishIM/tables/"
    private static let filePath = dir + "user_shortcuts.txt"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Hint
                VStack(alignment: .leading, spacing: 6) {
                    Text("把空碼變成你的快捷碼 skill — 打 2–4 碼直接輸出整段文字。")
                        .font(Typo.hint)
                    Text("適合綁定 agent 指令、prompt template、常用片語、簽名檔。")
                        .font(Typo.hint).foregroundStyle(.secondary)
                }

                // Demo examples
                GroupBox("範例") {
                    VStack(alignment: .leading, spacing: 4) {
                        demoRow("agpt", "請用繁體中文回答，並附上參考來源")
                        demoRow("amtg", "@channel 今天的 standup 更新如下：")
                        demoRow("acmd", "cd ~/Projects && git status")
                        demoRow("asig", "Best regards, — your name")
                    }
                    .padding(4)
                }

                addSection
                listSection
                Text("檔案路徑：~/Library/YabomishIM/tables/user_shortcuts.txt\n修改後輸入 ,,RL + 空白鍵 即時重載。")
                    .font(Typo.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .onAppear {
            loadShortcuts()
            countFreeCodes()
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
        GroupBox("新增快捷碼") {
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
                        .disabled(code.count < 2 || content.isEmpty)
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch codeStatus {
        case .empty: EmptyView()
        case .tooShort: Text("至少 2 碼").foregroundStyle(.secondary).font(Typo.caption)
        case .available: Text("✓ 可用").foregroundStyle(Typo.ok).font(Typo.caption)
        case .existsInCIN(let s): Text("字表已有：\(s)").foregroundStyle(Typo.warn).font(Typo.caption)
        case .existsInShortcuts(let s): Text("已有快捷碼，將覆蓋：\(s)").foregroundStyle(Typo.warn).font(Typo.caption)
        }
    }

    // MARK: - List Section

    private var listSection: some View {
        GroupBox("已建立的快捷碼") {
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
                            Button("🗑") { deleteShortcut(code: sc.code) }
                                .buttonStyle(.borderless)
                        }
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
            .padding(4)
        }
    }

    private var filtered: [(code: String, content: String)] {
        guard !search.isEmpty else { return shortcuts }
        let q = search.lowercased()
        return shortcuts.filter { $0.code.lowercased().contains(q) || $0.content.contains(q) }
    }

    // MARK: - Data

    private func loadShortcuts() {
        guard let text = try? String(contentsOfFile: Self.filePath, encoding: .utf8) else { return }
        shortcuts = text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (code: String(parts[0]), content: String(parts[1]))
        }
    }

    private func saveShortcuts() {
        try? FileManager.default.createDirectory(atPath: Self.dir, withIntermediateDirectories: true)
        let text = shortcuts.map { "\($0.code)\t\($0.content)" }.joined(separator: "\n")
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
        let paths = [
            "/Library/Input Methods/YabomishIM.app/Contents/Resources/liu.bin",
            NSHomeDirectory() + "/Library/YabomishIM/liu.bin",
        ]
        guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              data.count >= 16,
              data[0] == 0x43, data[1] == 0x49, data[2] == 0x4E, data[3] == 0x42
        else { return [] }
        let entryCount = Int(data.u32(4))
        let codesOff = Int(data.u32(8))
        var codes = Set<String>()
        for i in 0..<entryCount {
            let eo = codesOff + i * 6
            guard eo + 6 <= data.count else { break }
            let so = Int(data.u32(eo))
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
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        }
        for (c, v) in incoming {
            if let idx = shortcuts.firstIndex(where: { $0.code == c }) {
                shortcuts[idx] = (code: c, content: v)
            } else {
                shortcuts.append((code: c, content: v))
            }
        }
        saveShortcuts()
        countFreeCodes()
    }

    private func exportShortcuts() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "yabomish_快捷碼.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = shortcuts.map { "\($0.code)\t\($0.content)" }.joined(separator: "\n")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
