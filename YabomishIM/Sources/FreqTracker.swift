import Foundation
import SQLite3

final class FreqTracker {
    private var db: OpaquePointer?
    private let path: String
    private var recordCount = 0
    private let bgQueue = DispatchQueue(label: "com.yabomish.freq.bg")
    private var pendingFreq: [(code: String, char: String)] = []
    private var pendingBigram: [(prev: String, char: String)] = []
    private let batchSize = 50

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
        pendingFreq.append((code, char))
        recordCount += 1
        if pendingFreq.count >= batchSize { flushFreq() }
        if recordCount >= 500 { recordCount = 0; bgQueue.async { [weak self] in self?.decay() } }
    }

    func recordBigram(prev: String, char: String) {
        guard !prev.isEmpty else { return }
        pendingBigram.append((prev, char))
        if pendingBigram.count >= batchSize { flushBigram() }
    }

    func recordTrigram(prev2: String, prev1: String, char: String) {
        guard !prev2.isEmpty, !prev1.isEmpty else { return }
        pendingBigram.append((prev2 + "|" + prev1, char))
        if pendingBigram.count >= batchSize { flushBigram() }
    }

    private func flushFreq() {
        guard !pendingFreq.isEmpty else { return }
        exec("BEGIN")
        for (code, char) in pendingFreq { bindAndStep(stmtUpsertFreq, code, char) }
        exec("COMMIT")
        pendingFreq.removeAll(keepingCapacity: true)
    }

    private func flushBigram() {
        guard !pendingBigram.isEmpty else { return }
        exec("BEGIN")
        for (prev, char) in pendingBigram { bindAndStep(stmtUpsertBigram, prev, char) }
        exec("COMMIT")
        pendingBigram.removeAll(keepingCapacity: true)
    }

    func flushAll() { flushFreq(); flushBigram() }

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
        let uni = queryMap(stmtQueryFreq, code)
        let bi = queryMap(stmtQueryBigram, prev)
        guard !uni.isEmpty || !bi.isEmpty else { return candidates }
        let uniT = max(1.0, Double(uni.values.reduce(0, +)))
        let biT = max(1.0, Double(bi.values.reduce(0, +)))
        return candidates.sorted {
            backoffScore($0, uni, bi, uniT, biT) > backoffScore($1, uni, bi, uniT, biT)
        }
    }

    private func backoffScore(_ char: String, _ uni: [String: Int], _ bi: [String: Int],
                              _ uniT: Double, _ biT: Double) -> Double {
        if let b = bi[char] { return Double(b) / biT }
        return 0.4 * Double(uni[char] ?? 0) / uniT
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
        bgQueue.asyncAfter(deadline: .now() + 3) { [weak self] in
            #if os(iOS)
            guard MemoryBudget.canAfford(5) else { return }
            self?.mergeFromiCloud()
            #else
            self?.syncViaSyncFolder()
            #endif
        }
    }

    // MARK: - Migration from JSON

    private struct JSONStorage: Codable {
        let freq: [String: [String: Int]]
        let bigram: [String: [String: Int]]?
    }

    private func migrateFromJSON(dir: String) {
        let jsonPath = dir + "/freq.json"
        guard FileManager.default.fileExists(atPath: jsonPath) else { return }
        let data: Data
        do { data = try Data(contentsOf: URL(fileURLWithPath: jsonPath)) }
        catch { DebugLog.log("FreqTracker migrateFromJSON read: \(error.localizedDescription)"); return }
        // Backup first
        let backup = dir + "/freq.json.bak"
        if !FileManager.default.fileExists(atPath: backup) {
            try? FileManager.default.copyItem(atPath: jsonPath, toPath: backup)
        }
        do {
            let s = try JSONDecoder().decode(JSONStorage.self, from: data)
            importJSON(s)
            try? FileManager.default.removeItem(atPath: jsonPath)
        } catch {
            do {
                let legacyFreq = try JSONDecoder().decode([String: [String: Int]].self, from: data)
                importJSON(JSONStorage(freq: legacyFreq, bigram: nil))
                try? FileManager.default.removeItem(atPath: jsonPath)
            } catch { DebugLog.log("FreqTracker migrateFromJSON decode: \(error.localizedDescription)") }
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

    // MARK: - macOS Sync via syncFolder

    #if os(macOS)
    private func syncViaSyncFolder() {
        guard let dir = YabomishPrefs.syncFolder,
              FileManager.default.fileExists(atPath: dir) else { return }
        let jsonPath = dir + "/freq.json"
        // Import remote changes
        if FileManager.default.fileExists(atPath: jsonPath) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
                do { let remote = try JSONDecoder().decode(JSONStorage.self, from: data); importJSON(remote) }
                catch { DebugLog.log("FreqTracker syncViaSyncFolder decode: \(error.localizedDescription)") }
            } catch { DebugLog.log("FreqTracker syncViaSyncFolder read: \(error.localizedDescription)") }
        }
        // Export local state
        exportToJSON(path: jsonPath)
    }

    private func exportToJSON(path: String) {
        var freq: [String: [String: Int]] = [:]
        var bigram: [String: [String: Int]] = [:]
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT code, char, n FROM freq", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let code = String(cString: sqlite3_column_text(stmt, 0))
                let char = String(cString: sqlite3_column_text(stmt, 1))
                let n = Int(sqlite3_column_int(stmt, 2))
                freq[code, default: [:]][char] = n
            }
        }
        sqlite3_finalize(stmt)
        stmt = nil
        if sqlite3_prepare_v2(db, "SELECT prev, char, n FROM bigram", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let prev = String(cString: sqlite3_column_text(stmt, 0))
                let char = String(cString: sqlite3_column_text(stmt, 1))
                let n = Int(sqlite3_column_int(stmt, 2))
                bigram[prev, default: [:]][char] = n
            }
        }
        sqlite3_finalize(stmt)
        let storage = JSONStorage(freq: freq, bigram: bigram)
        if let data = try? JSONEncoder().encode(storage) {
            do { try data.write(to: URL(fileURLWithPath: path), options: .atomic) }
            catch { DebugLog.log("FreqTracker exportToJSON write: \(error.localizedDescription)") }
        }
    }
    #endif

    // MARK: - iCloud Sync

    #if os(iOS)
    private static var iCloudFreqURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents/freq.json")
    }

    private func mergeFromiCloud() {
        guard let url = Self.iCloudFreqURL else { return }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { DebugLog.log("FreqTracker mergeFromiCloud read: \(error.localizedDescription)"); return }
        do { let remote = try JSONDecoder().decode(JSONStorage.self, from: data); importJSON(remote) }
        catch { DebugLog.log("FreqTracker mergeFromiCloud decode: \(error.localizedDescription)") }
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
