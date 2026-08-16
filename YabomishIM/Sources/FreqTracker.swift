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
    private var stmtUpsertBigram: OpaquePointer?

    /// In-memory read caches — keystroke queries never touch SQLite or bgQueue.
    /// Mutated on bgQueue only; all access guarded by cacheLock.
    private let cacheLock = NSLock()
    private var freqCache: [String: [String: Int]] = [:]
    private var bigramCache: [String: [String: Int]] = [:]
    private var pinnedCache: [String: [String]] = [:]

    private var prefsObserver: Any?

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
        #if os(macOS)
        prefsObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.yabomish.prefsChanged"), object: nil, queue: .main
        ) { [weak self] _ in self?.reloadPinned() }
        #endif
        bgQueue.sync { loadAllCaches() }
    }

    deinit {
        #if os(macOS)
        if let prefsObserver {
            DistributedNotificationCenter.default().removeObserver(prefsObserver)
        }
        #endif
        sqlite3_finalize(stmtUpsertFreq)
        sqlite3_finalize(stmtUpsertBigram)
        sqlite3_finalize(stmtQueryPinned)
        sqlite3_finalize(stmtUpsertPinned)
        sqlite3_finalize(stmtDeletePinned)
        sqlite3_close(db)
    }

    // MARK: - DB Setup

    private var stmtQueryPinned: OpaquePointer?
    private var stmtUpsertPinned: OpaquePointer?
    private var stmtDeletePinned: OpaquePointer?

    private func openDB() {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            DebugLog.log("FreqTracker sqlite3_open failed: \(path)")
            return
        }
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")
        exec("CREATE TABLE IF NOT EXISTS freq(code TEXT, char TEXT, n INTEGER, PRIMARY KEY(code,char))")
        exec("CREATE TABLE IF NOT EXISTS bigram(prev TEXT, char TEXT, n INTEGER, PRIMARY KEY(prev,char))")
        exec("CREATE TABLE IF NOT EXISTS pinned(code TEXT PRIMARY KEY, chars TEXT NOT NULL)")
        // （不再內建任何字表衍生資料；固定排序一律由使用者 ,,PIN 自行設定）
        prepare("INSERT INTO freq(code,char,n) VALUES(?1,?2,1) ON CONFLICT(code,char) DO UPDATE SET n=n+1", &stmtUpsertFreq)
        prepare("INSERT INTO bigram(prev,char,n) VALUES(?1,?2,1) ON CONFLICT(prev,char) DO UPDATE SET n=n+1", &stmtUpsertBigram)
        prepare("SELECT chars FROM pinned WHERE code=?1", &stmtQueryPinned)
        prepare("INSERT OR REPLACE INTO pinned(code,chars) VALUES(?1,?2)", &stmtUpsertPinned)
        prepare("DELETE FROM pinned WHERE code=?1", &stmtDeletePinned)
    }

    /// Load freq/bigram/pinned into memory caches. Must run on bgQueue (or during init before concurrent access).
    private func loadAllCaches() {
        var freq: [String: [String: Int]] = [:]
        var bigram: [String: [String: Int]] = [:]
        var pinned: [String: [String]] = [:]
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT code, char, n FROM freq", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let code = String(cString: sqlite3_column_text(stmt, 0))
                freq[code, default: [:]][String(cString: sqlite3_column_text(stmt, 1))] = Int(sqlite3_column_int(stmt, 2))
            }
        }
        sqlite3_finalize(stmt); stmt = nil
        if sqlite3_prepare_v2(db, "SELECT prev, char, n FROM bigram", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let prev = String(cString: sqlite3_column_text(stmt, 0))
                bigram[prev, default: [:]][String(cString: sqlite3_column_text(stmt, 1))] = Int(sqlite3_column_int(stmt, 2))
            }
        }
        sqlite3_finalize(stmt); stmt = nil
        if sqlite3_prepare_v2(db, "SELECT code, chars FROM pinned", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let code = String(cString: sqlite3_column_text(stmt, 0))
                let chars = String(cString: sqlite3_column_text(stmt, 1))
                pinned[code] = Array(chars).map(String.init)
            }
        }
        sqlite3_finalize(stmt)
        cacheLock.lock()
        freqCache = freq
        bigramCache = bigram
        pinnedCache = pinned
        cacheLock.unlock()
    }

    /// Cached counts for a code/prev key — O(1) dict lookup, no SQLite, no queue hop.
    private func cachedFreq(_ key: String) -> [String: Int] {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return freqCache[key] ?? [:]
    }

    private func cachedBigram(_ key: String) -> [String: Int] {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return bigramCache[key] ?? [:]
    }

    // MARK: - Record

    func record(code: String, char: String) {
        // Cache updates synchronously (read-your-writes on the typing thread);
        // SQLite persistence stays batched on bgQueue.
        cacheLock.lock()
        freqCache[code, default: [:]][char, default: 0] += 1
        cacheLock.unlock()
        bgQueue.async { [weak self] in
            guard let self else { return }
            self.pendingFreq.append((code, char))
            self.recordCount += 1
            if self.pendingFreq.count >= self.batchSize { self.flushFreq() }
            if self.recordCount >= 500 { self.recordCount = 0; self.decay() }
        }
    }

    func recordBigram(prev: String, char: String) {
        guard !prev.isEmpty else { return }
        cacheLock.lock()
        bigramCache[prev, default: [:]][char, default: 0] += 1
        cacheLock.unlock()
        bgQueue.async { [weak self] in
            guard let self else { return }
            self.pendingBigram.append((prev, char))
            if self.pendingBigram.count >= self.batchSize { self.flushBigram() }
        }
    }

    func recordTrigram(prev2: String, prev1: String, char: String) {
        guard !prev2.isEmpty, !prev1.isEmpty else { return }
        let key = prev2 + "|" + prev1
        cacheLock.lock()
        bigramCache[key, default: [:]][char, default: 0] += 1
        cacheLock.unlock()
        bgQueue.async { [weak self] in
            guard let self else { return }
            self.pendingBigram.append((key, char))
            if self.pendingBigram.count >= self.batchSize { self.flushBigram() }
        }
    }

    /// Must be called on bgQueue
    private func flushFreq() {
        guard !pendingFreq.isEmpty else { return }
        exec("BEGIN")
        for (code, char) in pendingFreq { bindAndStep(stmtUpsertFreq, code, char) }
        exec("COMMIT")
        pendingFreq.removeAll(keepingCapacity: true)
    }

    /// Must be called on bgQueue
    private func flushBigram() {
        guard !pendingBigram.isEmpty else { return }
        exec("BEGIN")
        for (prev, char) in pendingBigram { bindAndStep(stmtUpsertBigram, prev, char) }
        exec("COMMIT")
        pendingBigram.removeAll(keepingCapacity: true)
    }

    func flushAll() { bgQueue.sync { flushFreq(); flushBigram() } }

    // MARK: - Query (pure in-memory; no SQLite, no queue hop)

    func sorted(_ candidates: [String], forCode code: String) -> [String] {
        if code.hasPrefix(",") { return candidates }
        let pinned = cachedPinned(code)
        let counts = cachedFreq(code)
        var result: [String]
        if !counts.isEmpty {
            result = candidates.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        } else {
            result = candidates
        }
        guard let pinned, !pinned.isEmpty else { return result }
        let pinSet = Set(pinned)
        let rest = result.filter { !pinSet.contains($0) }
        let front = pinned.filter { result.contains($0) }
        return front + rest
    }

    func sortedWithContext(_ candidates: [String], forCode code: String, prev: String) -> [String] {
        if code.hasPrefix(",") { return candidates }
        guard !prev.isEmpty else { return sorted(candidates, forCode: code) }
        let pinned = cachedPinned(code)
        let uni = cachedFreq(code)
        let bi = cachedBigram(prev)
        var result: [String]
        if uni.isEmpty && bi.isEmpty {
            result = candidates
        } else {
            let uniT = max(1.0, Double(uni.values.reduce(0, +)))
            let biT = max(1.0, Double(bi.values.reduce(0, +)))
            let biCount = bi.count
            let total = biCount + candidates.count
            let alpha: Double = total < 100 ? 0.4 : Double(candidates.count) / Double(total)
            var scores: [String: Double] = [:]
            for c in candidates {
                if let b = bi[c] {
                    scores[c] = Double(b) / biT
                } else {
                    scores[c] = alpha * Double(uni[c] ?? 0) / uniT
                }
            }
            result = candidates.sorted { (scores[$0] ?? 0) > (scores[$1] ?? 0) }
        }
        guard let pinned, !pinned.isEmpty else { return result }
        let pinSet = Set(pinned)
        let rest = result.filter { !pinSet.contains($0) }
        let front = pinned.filter { result.contains($0) }
        return front + rest
    }

    /// Top N learned bigram suggestions for a given prev char
    func topBigrams(prev: String, limit: Int = 3) -> [String] {
        guard !prev.isEmpty else { return [] }
        let counts = cachedBigram(prev)
        guard !counts.isEmpty else { return [] }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
    }

    /// Reorder suggestion candidates by bigram frequency (learned from user selections)
    /// Stable: only moves candidates with recorded bigram to front; rest keep original order.
    func bigramBoost(prev: String, candidates: [String]) -> [String] {
        guard !prev.isEmpty else { return candidates }
        let counts = cachedBigram(prev)
        guard !counts.isEmpty else { return candidates }
        var boosted = candidates.filter { counts[$0] != nil }.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        let rest = candidates.filter { counts[$0] == nil }
        boosted.append(contentsOf: rest)
        return boosted
    }

    // MARK: - Pinned order

    /// Reload pinned cache from DB (called when prefs change from external app).
    func reloadPinned() {
        bgQueue.sync { loadAllCaches() }
    }

    private func cachedPinned(_ code: String) -> [String]? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return pinnedCache[code]
    }

    /// Set pinned order for a code. chars is the ordered list of characters.
    func pin(code: String, chars: [String]) {
        let joined = chars.joined()
        bgQueue.sync {
            guard let stmt = stmtUpsertPinned else { return }
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, code, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, joined, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            cacheLock.lock()
            pinnedCache[code] = chars
            cacheLock.unlock()
        }
    }

    /// Remove pinned order for a code.
    func unpin(code: String) {
        bgQueue.sync {
            guard let stmt = stmtDeletePinned else { return }
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, code, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            cacheLock.lock()
            pinnedCache.removeValue(forKey: code)
            cacheLock.unlock()
        }
    }

    /// Get pinned chars for a code (from cache).
    func pinnedChars(forCode code: String) -> [String]? {
        cachedPinned(code)
    }

    // MARK: - Maintenance (all run on bgQueue; flush first so cache reload sees final DB state)

    func decay(factor: Double = 0.9) {
        flushFreq(); flushBigram()
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE freq SET n=MAX(1,CAST(n*?1 AS INTEGER))", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, factor)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        exec("DELETE FROM freq WHERE n<1")
        // Prune entries that have decayed to minimum (n=1) to prevent unbounded growth
        exec("DELETE FROM freq WHERE n<=1 AND rowid NOT IN (SELECT rowid FROM freq ORDER BY n DESC LIMIT 5000)")
        if sqlite3_prepare_v2(db, "UPDATE bigram SET n=MAX(1,CAST(n*?1 AS INTEGER))", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, factor)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        exec("DELETE FROM bigram WHERE n<1")
        exec("DELETE FROM bigram WHERE n<=1 AND rowid NOT IN (SELECT rowid FROM bigram ORDER BY n DESC LIMIT 5000)")
        loadAllCaches()
    }

    func reset() {
        bgQueue.sync {
            pendingFreq.removeAll(keepingCapacity: true)
            pendingBigram.removeAll(keepingCapacity: true)
            exec("DELETE FROM freq")
            exec("DELETE FROM bigram")
            recordCount = 0
            cacheLock.lock()
            freqCache.removeAll(keepingCapacity: true)
            bigramCache.removeAll(keepingCapacity: true)
            cacheLock.unlock()
        }
    }

    func saveIfNeeded() {
        // SQLite WAL auto-flushes; kept for API compat
    }

    func deferredMerge() {
        bgQueue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.flushFreq(); self.flushBigram() // persist pending before export/import
            #if os(iOS)
            guard MemoryBudget.canAfford(5) else { return }
            self.mergeFromiCloud()
            #else
            self.syncViaSyncFolder()
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

    /// Runs on bgQueue (deferredMerge) or during init; reload caches so imports are visible.
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
        loadAllCaches()
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
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
