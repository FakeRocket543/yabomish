import Foundation
import SQLite3

/// NER 詞組查詢 + 社群上下文追蹤（Layer 2 & 3）
final class PhraseLookup {
    static let shared = PhraseLookup()

    private var db: OpaquePointer?
    /// Session 社群計數：community_id → 累計權重
    private var sessionCommunities: [Int: Int] = [:]

    private init() {
        let userPath = NSHomeDirectory() + "/Library/Application Support/YabomishIM/yabomish_ime.db"
        let bundlePath = Bundle.main.path(forResource: "yabomish_ime", ofType: "db")
        let path = FileManager.default.fileExists(atPath: userPath) ? userPath : bundlePath

        guard let p = path else {
            DebugLog.log("YabomishIM: yabomish_ime.db not found")
            return
        }
        guard sqlite3_open_v2(p, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            DebugLog.log("YabomishIM: failed to open yabomish_ime.db")
            return
        }
        sqlite3_exec(db, "PRAGMA cache_size=-4000", nil, nil, nil) // 4MB cache
        DebugLog.log("YabomishIM: PhraseLookup loaded")
    }

    deinit { if let db = db { sqlite3_close(db) } }

    // MARK: - Zhuyin hash (must match Python build_ime_db.py)

    private func zyHash(_ zhuyinKey: String) -> Int64 {
        var hash: [UInt8] = Array(repeating: 0, count: 20)
        let data = Array(zhuyinKey.utf8)
        _ = data.withUnsafeBufferPointer { buf in
            CC_SHA1(buf.baseAddress, CC_LONG(buf.count), &hash)
        }
        // First 8 bytes as little-endian Int64
        return hash.withUnsafeBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: Int64.self, capacity: 1) { $0.pointee }
        }
    }

    // MARK: - Layer 2: NER Phrase Lookup

    /// 查詢完全匹配的 NER 詞組
    func phrasesForZhuyin(_ zhuyins: [String]) -> [(phrase: String, freq: Int, community: Int)] {
        guard let db = db else { return [] }
        let h = zyHash(zhuyins.joined())
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db,
            "SELECT phrase, freq, community FROM ner_phrase WHERE zy_hash=? ORDER BY freq DESC LIMIT 15",
            -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_int64(stmt, 1, h)
        var results: [(String, Int, Int)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let phrase = String(cString: sqlite3_column_text(stmt, 0))
            let freq = Int(sqlite3_column_int(stmt, 1))
            let comm = Int(sqlite3_column_int(stmt, 2))
            results.append((phrase, freq, comm))
        }
        return results
    }

    // MARK: - Layer 3: Community Context

    /// 查詢實體所屬社群
    func communityFor(_ entity: String) -> Int? {
        guard let db = db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db,
            "SELECT community FROM community WHERE entity=? LIMIT 1",
            -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, entity, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return nil
    }

    /// 使用者 commit 文字後更新社群上下文
    func updateContext(committed text: String) {
        // 整段文字作為實體查詢（強信號）
        if let c = communityFor(text) {
            sessionCommunities[c, default: 0] += 3
        }
        // 單字也查（弱信號）
        if text.count > 1 {
            for ch in text {
                if let c = communityFor(String(ch)) {
                    sessionCommunities[c, default: 0] += 1
                }
            }
        }
    }

    /// 取得社群加分：如果候選詞屬於活躍社群，回傳 > 0 的分數
    func communityBoost(for entity: String) -> Double {
        guard !sessionCommunities.isEmpty else { return 0 }
        guard let c = communityFor(entity) else { return 0 }
        guard let count = sessionCommunities[c] else { return 0 }
        let total = sessionCommunities.values.reduce(0, +)
        return Double(count) / Double(total)
    }

    /// 重置 session（切換 app 或長時間不用時）
    func resetSession() {
        sessionCommunities.removeAll()
    }

    /// NER 詞組前綴補全：輸入已 commit 的文字，回傳可能的詞組補全
    func completions(for prefix: String, limit: Int = 5) -> [String] {
        guard let db = db, prefix.count >= 2 else { return [] }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db,
            "SELECT phrase, freq FROM ner_phrase WHERE phrase LIKE ? AND phrase != ? ORDER BY freq DESC LIMIT ?",
            -1, &stmt, nil) == SQLITE_OK else { return [] }
        let pattern = prefix + "%"
        sqlite3_bind_text(stmt, 1, pattern, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, prefix, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int(stmt, 3, Int32(limit))
        var results: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return results
    }

    var hasActiveContext: Bool { !sessionCommunities.isEmpty }
}

// MARK: - CommonCrypto SHA1 bridge
import CommonCrypto
