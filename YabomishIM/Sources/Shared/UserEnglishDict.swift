import Foundation

/// User-added English words with creation dates（移植自 yabomish iOS 版）。
/// Stored as JSON at <dir>/user_english_dict.json。
/// 不依賴 AppConstants — init 帶目錄，IM 與 Prefs app 兩個 target 都能編。
final class UserEnglishDict {

    struct Entry: Codable {
        let word: String
        let date: String  // ISO8601 date, e.g. "2026-05-25"
    }

    private var entries: [String: Entry] = [:]  // lowercased word → Entry
    private let filePath: String

    init(dir: String) {
        filePath = dir + "/user_english_dict.json"
        load()
    }

    var count: Int { entries.count }

    /// 全部詞（排序後），設定程式的列表/匯出用。
    var allWords: [String] { entries.keys.sorted() }

    func contains(_ word: String) -> Bool {
        entries[word.lowercased()] != nil
    }

    func add(_ word: String) {
        let key = word.lowercased()
        guard !key.isEmpty, entries[key] == nil else { return }
        entries[key] = Entry(word: key, date: Self.todayString())
        save()
    }

    func remove(_ word: String) {
        entries.removeValue(forKey: word.lowercased())
        save()
    }

    func removeAll() {
        entries.removeAll()
        save()
    }

    /// Prefix search, returns words sorted alphabetically.
    func search(prefix: String, limit: Int = 8) -> [String] {
        let p = prefix.lowercased()
        guard !p.isEmpty else { return [] }
        return entries.keys
            .filter { $0.hasPrefix(p) && $0 != p }
            .sorted()
            .prefix(limit)
            .map { String($0) }
    }

    // MARK: - Export/Import

    /// Export as JSON string (for sharing/backup).
    func exportJSON() -> String {
        let sorted = entries.values.sorted { $0.word < $1.word }
        guard let data = try? JSONEncoder().encode(sorted),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    /// Import from JSON string. Merges with existing (keeps earlier date if duplicate).
    @discardableResult
    func importJSON(_ json: String) -> Int {
        guard let data = json.data(using: .utf8),
              let imported = try? JSONDecoder().decode([Entry].self, from: data) else { return 0 }
        var added = 0
        for entry in imported {
            let key = entry.word.lowercased()
            if entries[key] == nil {
                entries[key] = Entry(word: key, date: entry.date)
                added += 1
            }
        }
        if added > 0 { save() }
        return added
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        for entry in list { entries[entry.word.lowercased()] = entry }
    }

    private func save() {
        let list = Array(entries.values)
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
    }

    private static func todayString() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}
