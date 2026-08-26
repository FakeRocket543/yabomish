import Foundation
import SQLite3

/// 打字練習資料層：載入使用者自備的拆碼表（liu.bin）與公共語料字頻，
/// 生成練習題目。不隨附任何表格資料——與輸入法本體同原則，讀使用者已安裝的字表。
final class DrillEngine {
    enum Source: String, CaseIterable, Identifiable {
        case common = "常用字"
        case short = "一二碼字"
        case weak = "弱點字"
        case random = "隨機字"
        var id: String { rawValue }
    }

    struct Item: Identifiable {
        let id = UUID()
        let char: String
        let codes: [String]   // 該字所有合法碼（碼長遞增）
    }

    private(set) var charCodes: [String: [String]] = [:]     // char → codes（碼長遞增）
    private(set) var freq: [String: Int] = [:]               // 公共語料出現次數
    private(set) var tableLoaded = false
    private(set) var freqLoaded = false

    static let userDir: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Yabomish").path
    }()

    /// 回傳載入失敗原因（nil＝成功）
    @discardableResult
    func load() -> String? {
        loadTable()
        loadFreq()
        if !tableLoaded { return "找不到拆碼表 liu.bin——請先安裝 Yabomish 輸入法並匯入字表" }
        return nil
    }

    // MARK: - liu.bin 反向索引

    private func tableCandidates() -> [String] {
        [
            "/Library/Input Methods/YabomishIM.app/Contents/Resources/liu.bin",
            Self.userDir + "/liu.bin",
            NSHomeDirectory() + "/Library/YabomishIM/liu.bin",
        ]
    }

    private func loadTable() {
        guard let path = tableCandidates().first(where: { FileManager.default.fileExists(atPath: $0) }),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              data.count >= 128,
              data[0] == 0x43, data[1] == 0x49, data[2] == 0x4E, data[3] == 0x4D  // CINM
        else { return }

        let entryCount = Int(u32(data, 4))
        let codesOff = Int(u32(data, 96))
        let valsOff = Int(u32(data, 100))
        let stringsOff = Int(u32(data, 104))
        let charsOff = Int(u32(data, 108))

        var map: [String: [String]] = [:]
        map.reserveCapacity(entryCount * 2)
        for i in 0..<entryCount {
            let eo = codesOff + i * 6
            guard eo + 6 <= data.count else { break }
            let so = stringsOff + Int(u32(data, eo))
            let sl = Int(u16(data, eo + 4))
            guard so + sl <= data.count else { continue }
            guard let code = String(bytes: data[so..<so+sl], encoding: .utf8)?.lowercased(), !code.isEmpty else { continue }
            let ve = valsOff + i * 4
            guard ve + 3 <= data.count else { continue }
            let vOff = Int(u16(data, ve))
            let vCnt = Int(data[ve + 2])
            for j in 0..<vCnt {
                let off = charsOff + (vOff + j) * 4
                guard off + 4 <= data.count else { break }
                if let s = Unicode.Scalar(u32(data, off)).map(String.init) {
                    map[s, default: []].append(code)
                }
            }
        }
        // 每字碼表：短碼優先（常用短碼先熟的漸進精神）
        for (k, v) in map { map[k] = v.sorted { ($0.count, $0) < ($1.count, $1) } }
        charCodes = map
        tableLoaded = !map.isEmpty
    }

    // MARK: - 字頻（公共語料統計，本專案自有資料）

    private func loadFreq() {
        guard let data = FileManager.default.contents(atPath: Self.userDir + "/char_freq.json"),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return }
        freq = decoded
        freqLoaded = true
    }

    // MARK: - 弱點來源

    /// 查字歷史最近記錄的字
    private func lookupHistoryChars(limit: Int) -> [String] {
        var out: [String] = []
        var db: OpaquePointer?
        guard sqlite3_open_v2(Self.userDir + "/freq.db", &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return out }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT char FROM lookup_history ORDER BY id DESC LIMIT \(max(1, limit))", -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return out
    }

    // MARK: - 錯字收集（練習打錯的字自動進弱點池）

    private static var wrongLogPath: String { Self.userDir + "/practice_wrong.json" }

    /// 本輪答錯的字寫入弱點池（去重、上限 300、新的在前）
    func collectWrong(_ chars: [String]) {
        var existing = loadWrongLog()
        for ch in chars {
            existing.removeAll { $0 == ch }
            existing.insert(ch, at: 0)
        }
        if existing.count > 300 { existing = Array(existing.prefix(300)) }
        if let data = try? JSONEncoder().encode(existing) {
            try? data.write(to: URL(fileURLWithPath: Self.wrongLogPath), options: .atomic)
        }
    }

    private func loadWrongLog() -> [String] {
        guard let data = FileManager.default.contents(atPath: Self.wrongLogPath),
              let list = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return list
    }

    // MARK: - 出題

    /// 產生一輪題目。回傳 error 表示該題源無可用題（附原因）。
    func makeRound(source: Source, count: Int) -> (items: [Item], error: String?) {
        guard count >= 1 else { return ([], "題數需 ≥ 1") }
        let pool: [String]
        switch source {
        case .common:
            pool = freq.keys.filter { charCodes[$0] != nil }
                .sorted { (freq[$0] ?? 0, $0) > (freq[$1] ?? 0, $1) }
                .prefix(200)
                .map { $0 }
            if pool.isEmpty { return ([], "無題——字頻資料或拆碼表缺漏") }
        case .short:
            // 一二碼字：最短碼 ≤2 的高頻常用字（速練簡碼手感）
            pool = freq.keys.filter { c in
                guard let first = charCodes[c]?.first else { return false }
                return first.count <= 2
            }
            .sorted { (freq[$0] ?? 0, $0) > (freq[$1] ?? 0, $1) }
            .prefix(150)
            .map { $0 }
            if pool.isEmpty { return ([], "無題——找不到一、二碼的常用字") }
        case .weak:
            // 查字歷史 ∪ 練習錯字收集——兩個弱點來源合流
            var seen = Set<String>()
            let merged = (loadWrongLog() + lookupHistoryChars(limit: 300)).filter { seen.insert($0).inserted }
            pool = merged.filter { charCodes[$0] != nil }
            if pool.isEmpty { return ([], "查字歷史與錯字收集都還是空的——在輸入法查字或練習打錯後就會累積") }
        case .random:
            pool = Array(charCodes.keys)
            if pool.isEmpty { return ([], "拆碼表為空") }
        }
        let picked = pool.shuffled().prefix(max(1, count))
        let items = picked.map { Item(char: $0, codes: charCodes[$0] ?? []) }
        return (items, nil)
    }

    /// 自訂文章：依原文順序出題（不打亂、重複字照打），只收表內字。回傳 (題目, 跳過的不在表內字數)。
    func makeRoundFromArticle(_ text: String, cap: Int = 200) -> (items: [Item], skipped: Int, error: String?) {
        var items: [Item] = []
        var skipped = 0
        for ch in text {
            guard !(ch.isWhitespace || ch.isNewline) else { continue }
            guard let codes = charCodes[String(ch)], !codes.isEmpty else { skipped += 1; continue }
            items.append(Item(char: String(ch), codes: codes))
            if items.count >= max(1, cap) { break }
        }
        if items.isEmpty {
            return ([], skipped, "文章裡沒有可練習的字（都不在拆碼表內）")
        }
        return (items, skipped, nil)
    }
}

// CINM binary helpers（與 PinnedOrderSection 同款）
@inline(__always) private func u32(_ d: Data, _ o: Int) -> UInt32 {
    d.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt32.self) }
}
@inline(__always) private func u16(_ d: Data, _ o: Int) -> UInt16 {
    d.withUnsafeBytes { $0.load(fromByteOffset: o, as: UInt16.self) }
}
