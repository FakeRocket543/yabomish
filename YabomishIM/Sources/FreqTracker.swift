import Foundation
import SQLite3

final class FreqTracker {
    private var db: OpaquePointer?
    private let path: String
    private var recordCount = 0

    private var stmtUpsertFreq: OpaquePointer?
    private var stmtQueryFreq: OpaquePointer?
    private var stmtUpsertBigram: OpaquePointer?
    private var stmtQueryBigram: OpaquePointer?

    init() {
        // SQLite DB always in local App Support (never in iCloud/sync folder —
        // WAL mode is incompatible with cloud sync)
        let dir = AppConstants.sharedDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        self.path = dir + "/freq.db"
        openDB()
        migrateFromJSON(dir: dir)
        // Also check syncFolder for legacy freq.json to migrate
        if let sync = YabomishPrefs.syncFolder,
           sync != dir,
           FileManager.default.fileExists(atPath: sync + "/freq.json") {
            migrateFromJSON(dir: sync)
        }
    }

    deinit {
        sqlite3_finalize(stmtUpsertFreq)
        sqlite3_finalize(stmtQueryFreq)
        sqlite3_finalize(stmtUpsertBigram)
        sqlite3_finalize(stmtQueryBigram)
        sqlite3_close(db)
    }

    // MARK: - DB Setup

    private func openDB() {
        guard sqlite3_open(path, &db) == SQLITE_OK else { return }
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")
        exec("CREATE TABLE IF NOT EXISTS freq(code TEXT, char TEXT, n INTEGER, PRIMARY KEY(code,char))")
        exec("CREATE TABLE IF NOT EXISTS bigram(prev TEXT, char TEXT, n INTEGER, PRIMARY KEY(prev,char))")
        prepare("INSERT INTO freq(code,char,n) VALUES(?1,?2,1) ON CONFLICT(code,char) DO UPDATE SET n=n+1", &stmtUpsertFreq)
        prepare("SELECT char,n FROM freq WHERE code=?1 ORDER BY n DESC", &stmtQueryFreq)
        prepare("INSERT INTO bigram(prev,char,n) VALUES(?1,?2,1) ON CONFLICT(prev,char) DO UPDATE SET n=n+1", &stmtUpsertBigram)
        prepare("SELECT char,n FROM bigram WHERE prev=?1 ORDER BY n DESC", &stmtQueryBigram)
    }

    // MARK: - Record

    func record(code: String, char: String) {
        bindAndStep(stmtUpsertFreq, code, char)
        recordCount += 1
        if recordCount >= 500 { recordCount = 0; decay() }
    }

    func recordBigram(prev: String, char: String) {
        guard !prev.isEmpty else { return }
        bindAndStep(stmtUpsertBigram, prev, char)
    }

    func recordTrigram(prev2: String, prev1: String, char: String) {
        // Store as composite key "prev2|prev1" — lightweight trigram
        guard !prev2.isEmpty, !prev1.isEmpty else { return }
        bindAndStep(stmtUpsertBigram, prev2 + "|" + prev1, char)
    }

    // MARK: - Query

    func sorted(_ candidates: [String], forCode code: String) -> [String] {
        if code.hasPrefix(",") { return candidates }
        let counts = queryMap(stmtQueryFreq, code)
        guard !counts.isEmpty else { return candidates }
        return candidates.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
    }

    func sortedWithContext(_ candidates: [String], forCode code: String, prev: String) -> [String] {
        if code.hasPrefix(",") { return candidates }
        guard !prev.isEmpty else { return sorted(candidates, forCode: code) }
        let unigramCounts = queryMap(stmtQueryFreq, code)
        let bigramCounts = queryMap(stmtQueryBigram, prev)
        guard !unigramCounts.isEmpty || !bigramCounts.isEmpty else { return candidates }
        return candidates.sorted {
            let s0 = Double(unigramCounts[$0] ?? 0) * 0.7 + Double(bigramCounts[$0] ?? 0) * 0.3
            let s1 = Double(unigramCounts[$1] ?? 0) * 0.7 + Double(bigramCounts[$1] ?? 0) * 0.3
            return s0 > s1
        }
    }

    /// Top N learned bigram suggestions for a given prev char
    func topBigrams(prev: String, limit: Int = 3) -> [String] {
        guard !prev.isEmpty else { return [] }
        let counts = queryMap(stmtQueryBigram, prev)
        guard !counts.isEmpty else { return [] }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
    }

    /// Reorder suggestion candidates by bigram frequency (learned from user selections)
    /// Stable: only moves candidates with recorded bigram to front; rest keep original order.
    func bigramBoost(prev: String, candidates: [String]) -> [String] {
        guard !prev.isEmpty else { return candidates }
        let counts = queryMap(stmtQueryBigram, prev)
        guard !counts.isEmpty else { return candidates }
        var boosted = candidates.filter { counts[$0] != nil }.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        let rest = candidates.filter { counts[$0] == nil }
        boosted.append(contentsOf: rest)
        return boosted
    }

    // MARK: - Maintenance

    func decay(factor: Double = 0.9) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE freq SET n=CAST(n*?1 AS INTEGER)", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, factor)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        exec("DELETE FROM freq WHERE n<1")
        if sqlite3_prepare_v2(db, "UPDATE bigram SET n=CAST(n*?1 AS INTEGER)", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, factor)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        exec("DELETE FROM bigram WHERE n<1")
    }

    func reset() {
        exec("DELETE FROM freq")
        exec("DELETE FROM bigram")
        recordCount = 0
    }

    func saveIfNeeded() {
        // SQLite WAL auto-flushes; kept for API compat
    }

    func deferredMerge() {
        #if os(iOS)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { [weak self] in
            guard MemoryBudget.canAfford(5) else { return }
            self?.mergeFromiCloud()
        }
        #endif
    }

    // MARK: - Migration from JSON

    private struct JSONStorage: Codable {
        let freq: [String: [String: Int]]
        let bigram: [String: [String: Int]]?
    }

    private func migrateFromJSON(dir: String) {
        let jsonPath = dir + "/freq.json"
        guard FileManager.default.fileExists(atPath: jsonPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)) else { return }
        // Backup first
        let backup = dir + "/freq.json.bak"
        if !FileManager.default.fileExists(atPath: backup) {
            try? FileManager.default.copyItem(atPath: jsonPath, toPath: backup)
        }
        if let s = try? JSONDecoder().decode(JSONStorage.self, from: data) {
            importJSON(s)
            try? FileManager.default.removeItem(atPath: jsonPath)
        } else if let legacyFreq = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            importJSON(JSONStorage(freq: legacyFreq, bigram: nil))
            try? FileManager.default.removeItem(atPath: jsonPath)
        }
    }

    private func importJSON(_ s: JSONStorage) {
        exec("BEGIN")
        for (code, counts) in s.freq {
            for (char, n) in counts { upsertMax("freq", code, char, n) }
        }
        if let bg = s.bigram {
            for (prev, counts) in bg {
                for (char, n) in counts { upsertMax("bigram", prev, char, n) }
            }
        }
        exec("COMMIT")
    }

    private func upsertMax(_ table: String, _ key: String, _ char: String, _ n: Int) {
        let col1 = table == "bigram" ? "prev" : "code"
        let sql = "INSERT INTO \(table)(\(col1),char,n) VALUES(?1,?2,?3) ON CONFLICT(\(col1),char) DO UPDATE SET n=MAX(n,?3)"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, char, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(n))
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - iCloud Sync

    #if os(iOS)
    private static var iCloudFreqURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents/freq.json")
    }

    private func mergeFromiCloud() {
        guard let url = Self.iCloudFreqURL,
              let data = try? Data(contentsOf: url),
              let remote = try? JSONDecoder().decode(JSONStorage.self, from: data) else { return }
        importJSON(remote)
    }
    #endif

    // MARK: - SQLite Helpers

    private func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }
    private func prepare(_ sql: String, _ stmt: inout OpaquePointer?) { sqlite3_prepare_v2(db, sql, -1, &stmt, nil) }

    private func bindAndStep(_ stmt: OpaquePointer?, _ key: String, _ char: String) {
        guard let stmt else { return }
        sqlite3_reset(stmt)
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, char, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    private func queryMap(_ stmt: OpaquePointer?, _ key: String) -> [String: Int] {
        guard let stmt else { return [:] }
        sqlite3_reset(stmt)
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        var result: [String: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            result[String(cString: sqlite3_column_text(stmt, 0))] = Int(sqlite3_column_int(stmt, 1))
        }
        return result
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
