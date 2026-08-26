import Foundation

/// 練習成績記錄：存使用者目錄 practice_history.json，顯示最近走勢。
struct SessionRecord: Codable, Identifiable {
    var id = UUID()
    let ts: Date
    let mode: String
    let total: Int
    let correct: Int
    let seconds: Double
    /// 每分鐘字數（以正確字數計）
    var kpm: Double { seconds > 0 ? Double(correct) / (seconds / 60) : 0 }
    var accuracy: Double { total > 0 ? Double(correct) / Double(total) : 0 }
}

enum StatsStore {
    private static let path = DrillEngine.userDir + "/practice_history.json"

    static func append(_ r: SessionRecord) {
        var all = loadAll()
        all.append(r)
        if all.count > 200 { all = Array(all.suffix(200)) }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        if let data = try? enc.encode(all) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    static func recent(_ n: Int = 10) -> [SessionRecord] {
        Array(loadAll().suffix(n))
    }

    private static func loadAll() -> [SessionRecord] {
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return (try? dec.decode([SessionRecord].self, from: data)) ?? []
    }
}
