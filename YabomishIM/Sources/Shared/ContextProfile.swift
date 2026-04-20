import Foundation

/// A snapshot of all context-sensitive settings (input mode, suggestion, domains).
struct ContextProfile: Codable, Identifiable {
    var id: String { code }

    var version: Int = 1
    var name: String
    var icon: String
    var code: String
    var inputMode: String = "t"
    var suggestEnabled: Bool = true
    var suggestStrategy: String = "general"
    var charSuggest: Bool = true
    var wordCorpus: String = "wiki"
    var regionVariant: String = "tw"
    var fuzzyMatch: Bool = true
    var autoCommit: Bool = false
    var domainOrder: [String] = []
    var domainEnabled: [String: Bool] = [:]

    static let reservedCodes: Set<String> = ["xs", "xi", "rs"]
    static let maxProfiles = 10

    // MARK: - Paths

    static func contextsDir() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Yabomish/contexts").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func path(for code: String) -> String {
        contextsDir() + "/\(code).json"
    }

    // MARK: - CRUD

    static func loadAll() -> [ContextProfile] {
        let dir = contextsDir()
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return files.filter { $0.hasSuffix(".json") }.compactMap { file in
            let p = dir + "/" + file
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: p)) else { return nil }
            return try? JSONDecoder().decode(ContextProfile.self, from: data)
        }
    }

    static func load(code: String) -> ContextProfile? {
        let p = path(for: code)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: p)) else { return nil }
        return try? JSONDecoder().decode(ContextProfile.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let p = Self.path(for: code)
        try? data.write(to: URL(fileURLWithPath: p))
    }

    func delete() {
        try? FileManager.default.removeItem(atPath: Self.path(for: code))
    }

    // MARK: - Snapshot current settings

    static func snapshotCurrent(name: String = "", icon: String = "", code: String = "") -> ContextProfile {
        let ud = UserDefaults.standard
        var p = ContextProfile(name: name, icon: icon, code: code)
        p.suggestEnabled = ud.object(forKey: "suggestEnabled") as? Bool ?? true
        p.suggestStrategy = ud.string(forKey: "suggestStrategy") ?? "general"
        p.charSuggest = ud.object(forKey: "charSuggest") as? Bool ?? true
        p.wordCorpus = ud.string(forKey: "wordCorpus") ?? "wiki"
        p.regionVariant = ud.string(forKey: "regionVariant") ?? "tw"
        p.fuzzyMatch = ud.object(forKey: "fuzzyMatch") as? Bool ?? true
        p.autoCommit = ud.object(forKey: "autoCommit") as? Bool ?? false
        p.domainOrder = ud.stringArray(forKey: "domainOrder") ?? []
        // Collect domain_* keys
        var enabled: [String: Bool] = [:]
        for (key, val) in ud.dictionaryRepresentation() {
            if key.hasPrefix("domain_"), !key.hasSuffix("_pri"), let b = val as? Bool {
                enabled[key] = b
            }
        }
        p.domainEnabled = enabled
        return p
    }

    // MARK: - Default profiles

    static func createDefaults() {
        let dir = contextsDir()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.filter { $0.hasSuffix(".json") } ?? []
        guard files.isEmpty else { return }

        let defaults: [ContextProfile] = [
            ContextProfile(name: "預設", icon: "⌨️", code: "df",
                           suggestStrategy: "general",
                           domainOrder: [],
                           domainEnabled: [:]),
            ContextProfile(name: "台式", icon: "🇹🇼", code: "tw",
                           suggestStrategy: "general",
                           domainOrder: ["domain_phrases", "domain_chengyu", "domain_ner", "domain_kautian", "domain_placename", "domain_jingjing"],
                           domainEnabled: ["domain_phrases": true, "domain_chengyu": true, "domain_ner": true, "domain_kautian": true, "domain_placename": true, "domain_jingjing": true]),
            ContextProfile(name: "中式", icon: "🇨🇳", code: "ch", inputMode: "s",
                           suggestStrategy: "general",
                           regionVariant: "cn",
                           domainOrder: ["domain_phrases", "domain_cn_slang", "domain_ner"],
                           domainEnabled: ["domain_phrases": true, "domain_cn_slang": true, "domain_ner": true]),
            ContextProfile(name: "科技", icon: "💻", code: "tc",
                           suggestStrategy: "domain",
                           domainOrder: ["domain_it", "domain_ee", "domain_math", "domain_jingjing", "domain_ner"],
                           domainEnabled: ["domain_it": true, "domain_ee": true, "domain_math": true, "domain_jingjing": true, "domain_ner": true]),
        ]
        for p in defaults { p.save() }
    }
}
