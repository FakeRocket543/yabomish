import Foundation

/// Wiki corpus: trigram suggestions + NER phrase completion via mmap binary files.
final class WikiCorpus {
    static let shared = WikiCorpus()

    private let prefs: IMEPreferences

    // Trigram
    private var tgData: Data?
    private var tgKeyCount = 0
    private var tgKeysOff = 0
    private var tgOffsetsOff = 0
    private var tgCountsOff = 0
    private var tgValuesOff = 0

    // NER
    private var nerData: Data?
    private var nerKeyCount = 0
    private var nerKeysOff = 0
    private var nerOffsetsOff = 0
    private var nerCountsOff = 0
    private var nerPhrasesOff = 0

    // Phrase dictionary
    private var phData: Data?
    private var phKeyCount = 0
    private var phKeysOff = 0
    private var phOffsetsOff = 0
    private var phCountsOff = 0
    private var phPhrasesOff = 0

    // Word n-gram (WBMM)
    private var wbData: Data?
    private var wbKeyCount = 0
    private var wbKeyIndexOff = 0
    private var wbValIndexOff = 0

    // Chengyu (WBMM)
    private var cyData: Data?
    private var cyKeyCount = 0
    private var cyKeyIndexOff = 0
    private var cyValIndexOff = 0

    // Emoji char map
    private var emojiMap: [String: [String]] = [:]
    private struct DomainBin { let data: Data; let keyCount: Int; let keyIndexOff: Int; let valIndexOff: Int; let priority: Int }
    private var domainBins: [DomainBin] = []
    var domainBinCount: Int { domainBins.count }

    // Word-level news corpus (WBMM)
    private var wnData: Data?
    private var wnKeyCount = 0
    private var wnKeyIndexOff = 0
    private var wnValIndexOff = 0

    /// All domain/corpus bins available for the third layer (checkbox + priority)
    /// Group 1: 一般詞庫
    static let generalDomainKeys: [(key: String, file: String, label: String)] = [
        ("domain_ner", "ner_phrases", "NER 詞組"),
        ("domain_phrases", "phrases", "萌典詞組"),
        ("domain_chengyu", "chengyu", "成語"),
        ("domain_yoji", "yoji", "日式四字熟語"),
        ("domain_cn_slang", "terms_cn_slang", "中式流行語"),
    ]
    /// Group 2: 專業詞典
    static let proDomainKeys: [(key: String, file: String, label: String)] = [
        ("domain_it", "terms_it", "資訊科技"), ("domain_ee", "terms_ee", "電機電子"),
        ("domain_med", "terms_med", "醫學"), ("domain_law", "terms_law", "法律"),
        ("domain_phy", "terms_phy", "物理∕計量"), ("domain_chem", "terms_chem", "化學"),
        ("domain_bio", "terms_bio", "生物"), ("domain_math", "terms_math", "數學"),
        ("domain_biz", "terms_biz", "商業金融"), ("domain_edu", "terms_edu", "教育"),
        ("domain_geo", "terms_geo", "地理"), ("domain_eng", "terms_eng", "工程"),
        ("domain_art", "terms_art", "藝術"), ("domain_mil", "terms_mil", "軍事"),
        ("domain_marine", "terms_marine", "海事"),
        ("domain_material", "terms_material", "材料∕礦物"),
        ("domain_agri", "terms_agri", "農林畜牧"),
        ("domain_media", "terms_media", "新聞傳播"),
        ("domain_social", "terms_social", "社會行政"),
        ("domain_govt", "terms_govt", "政府機關"),
    ]
    /// All keys combined
    static let domainKeys: [(key: String, file: String, label: String)] = generalDomainKeys + proDomainKeys

    init(prefs: IMEPreferences = DefaultPreferences.shared) {
        self.prefs = prefs
        loadTrigram()
        loadWordBigram()
        loadWordNews()
        loadEmojiMap()
        reloadDomains()
    }

    private func resolvePath(name: String, ext: String) -> String? {
        let shared = AppConstants.sharedDir + "/\(name).\(ext)"
        if FileManager.default.fileExists(atPath: shared) { return shared }
        return Bundle.main.path(forResource: name, ofType: ext)
    }

    private func loadEmojiMap() {
        guard let p = resolvePath(name: "emoji_char_map", ext: "json") else { return }
        let d: Data
        do { d = try Data(contentsOf: URL(fileURLWithPath: p)) }
        catch { DebugLog.log("WikiCorpus loadEmojiMap: \(error.localizedDescription)"); return }
        guard let obj = try? JSONSerialization.jsonObject(with: d) as? [String: [String]] else { return }
        emojiMap = obj
    }

    func suggestEmoji(for char: String, limit: Int = 2) -> [String] {
        Array((emojiMap[char] ?? []).prefix(limit))
    }

    func reloadDomains() {
        domainBins.removeAll()
        nerData = nil; nerKeyCount = 0
        phData = nil; phKeyCount = 0
        // Use DomainOrderManager order (drag-reorder position = priority)
        let orderedKeys = DomainOrderManager.shared.allOrderedKeys()
        let keyToFile = Dictionary(uniqueKeysWithValues: Self.domainKeys.map { ($0.key, $0.file) })
        for key in orderedKeys {
            guard prefs.domainEnabled(key),
                  let file = keyToFile[key] else { continue }
            if key == "domain_ner" { loadNER(); continue }
            if key == "domain_phrases" { loadPhrases(); continue }
            guard let p = resolvePath(name: file, ext: "bin") else { continue }
            let d: Data
            do { d = try Data(contentsOf: URL(fileURLWithPath: p), options: .mappedIfSafe) }
            catch { DebugLog.log("WikiCorpus reloadDomains \(file): \(error.localizedDescription)"); continue }
            guard d.count >= 16, d[0] == 0x57, d[1] == 0x42, d[2] == 0x4D, d[3] == 0x4D else { continue }
            let ki = Int(d.u32(8)), vi = Int(d.u32(12))
            guard ki >= 16, ki < vi, vi <= d.count else { continue }
            // priority = position in ordered list (no longer uses domainPriority pref)
            domainBins.append(DomainBin(data: d, keyCount: Int(d.u32(4)),
                                        keyIndexOff: ki, valIndexOff: vi, priority: domainBins.count))
        }
    }

    /// Query all enabled domain bins + NER/phrases, sorted by priority
    func suggestAllDomains(prefix: String, limit: Int = 5) -> [String] {
        var results: [String] = []
        var seen = Set<String>()

        // Collect (priority, results) pairs
        var ranked: [(pri: Int, vals: [String])] = []

        // NER phrases
        if nerData != nil && nerKeyCount > 0 {
            let pri = prefs.domainPriority("domain_ner")
            let hits = suggestPhrases(after: String(prefix.suffix(1)), limit: 5)
                .filter { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)) }
                .filter { !$0.isEmpty }
            if !hits.isEmpty { ranked.append((pri, hits)) }
        }

        // Phrase dictionary
        if phData != nil && phKeyCount > 0 {
            let pri = prefs.domainPriority("domain_phrases")
            let hits = phraseCompletions(for: prefix)
            if !hits.isEmpty { ranked.append((pri, hits)) }
        }

        // WBMM bins
        for bin in domainBins {
            let hits = queryWBMM(data: bin.data, keyCount: bin.keyCount, keyIndexOff: bin.keyIndexOff,
                                 valIndexOff: bin.valIndexOff, key: prefix, limit: 3)
            if !hits.isEmpty { ranked.append((bin.priority, hits)) }
        }

        ranked.sort { $0.pri < $1.pri }
        for (_, vals) in ranked {
            for v in vals where seen.insert(v).inserted {
                results.append(v)
                if results.count >= limit { return results }
            }
        }
        return results
    }

    func suggestDomainTerms(prefix: String, limit: Int = 3) -> [String] {
        guard !domainBins.isEmpty else { return [] }
        var results: [String] = []
        var seen = Set<String>()
        for bin in domainBins {
            for s in queryWBMM(data: bin.data, keyCount: bin.keyCount, keyIndexOff: bin.keyIndexOff,
                               valIndexOff: bin.valIndexOff, key: prefix, limit: limit - results.count)
            where seen.insert(s).inserted { results.append(s) }
            if results.count >= limit { return results }
        }
        return results
    }

    // MARK: - Load

    private func loadTrigram() {
        guard let p = resolvePath(name: "trigram", ext: "bin") else { return }
        let d: Data
        do { d = try Data(contentsOf: URL(fileURLWithPath: p), options: .mappedIfSafe) }
        catch { DebugLog.log("WikiCorpus loadTrigram: \(error.localizedDescription)"); return }
        guard d.count >= 12, d[0] == 0x54, d[1] == 0x47, d[2] == 0x4D, d[3] == 0x4D else { return }
        tgKeyCount = Int(d.u32(4))
        tgKeysOff = 8
        tgOffsetsOff = tgKeysOff + tgKeyCount * 8
        tgCountsOff = tgOffsetsOff + tgKeyCount * 4
        tgValuesOff = tgCountsOff + tgKeyCount * 2
        guard tgValuesOff <= d.count else { return }
        tgData = d
    }

    private func loadNER() {
        guard let p = resolvePath(name: "ner_phrases", ext: "bin") else { return }
        let d: Data
        do { d = try Data(contentsOf: URL(fileURLWithPath: p), options: .mappedIfSafe) }
        catch { DebugLog.log("WikiCorpus loadNER: \(error.localizedDescription)"); return }
        guard d.count >= 12, d[0] == 0x4E, d[1] == 0x52, d[2] == 0x4D, d[3] == 0x4D else { return }
        nerKeyCount = Int(d.u32(4))
        nerKeysOff = 8
        nerOffsetsOff = nerKeysOff + nerKeyCount * 4
        nerCountsOff = nerOffsetsOff + nerKeyCount * 4
        nerPhrasesOff = nerCountsOff + nerKeyCount * 2
        guard nerPhrasesOff <= d.count else { return }
        nerData = d
    }

    private func loadPhrases() {
        guard let p = resolvePath(name: "phrases", ext: "bin") else { return }
        let d: Data
        do { d = try Data(contentsOf: URL(fileURLWithPath: p), options: .mappedIfSafe) }
        catch { DebugLog.log("WikiCorpus loadPhrases: \(error.localizedDescription)"); return }
        guard d.count >= 12, d[0] == 0x50, d[1] == 0x48, d[2] == 0x4D, d[3] == 0x4D else { return }
        phKeyCount = Int(d.u32(4))
        phKeysOff = 8
        phOffsetsOff = phKeysOff + phKeyCount * 4
        phCountsOff = phOffsetsOff + phKeyCount * 4
        phPhrasesOff = phCountsOff + phKeyCount * 2
        guard phPhrasesOff <= d.count else { return }
        phData = d
    }

    private func loadWordBigram() {
        guard let p = resolvePath(name: "word_ngram", ext: "bin")
                    ?? resolvePath(name: "word_bigram", ext: "bin") else { return }
        let d: Data
        do { d = try Data(contentsOf: URL(fileURLWithPath: p), options: .mappedIfSafe) }
        catch { DebugLog.log("WikiCorpus loadWordBigram: \(error.localizedDescription)"); return }
        guard d.count >= 16, d[0] == 0x57, d[1] == 0x42, d[2] == 0x4D, d[3] == 0x4D else { return }
        wbKeyCount = Int(d.u32(4))
        wbKeyIndexOff = Int(d.u32(8))
        wbValIndexOff = Int(d.u32(12))
        guard wbKeyIndexOff >= 16, wbKeyIndexOff < wbValIndexOff, wbValIndexOff <= d.count else { return }
        wbData = d
    }

    private func loadChengyu() {
        guard let p = resolvePath(name: "chengyu", ext: "bin") else { return }
        let d: Data
        do { d = try Data(contentsOf: URL(fileURLWithPath: p), options: .mappedIfSafe) }
        catch { DebugLog.log("WikiCorpus loadChengyu: \(error.localizedDescription)"); return }
        guard d.count >= 16, d[0] == 0x57, d[1] == 0x42, d[2] == 0x4D, d[3] == 0x4D else { return }
        cyKeyCount = Int(d.u32(4))
        cyKeyIndexOff = Int(d.u32(8))
        cyValIndexOff = Int(d.u32(12))
        guard cyKeyIndexOff >= 16, cyKeyIndexOff < cyValIndexOff, cyValIndexOff <= d.count else { return }
        cyData = d
    }

    private func loadWordNews() {
        guard let p = resolvePath(name: "word_news", ext: "bin") else { return }
        let d: Data
        do { d = try Data(contentsOf: URL(fileURLWithPath: p), options: .mappedIfSafe) }
        catch { DebugLog.log("WikiCorpus loadWordNews: \(error.localizedDescription)"); return }
        guard d.count >= 16, d[0] == 0x57, d[1] == 0x42, d[2] == 0x4D, d[3] == 0x4D else { return }
        wnKeyCount = Int(d.u32(4))
        wnKeyIndexOff = Int(d.u32(8))
        wnValIndexOff = Int(d.u32(12))
        guard wnKeyIndexOff >= 16, wnKeyIndexOff < wnValIndexOff, wnValIndexOff <= d.count else { return }
        wnData = d
    }

    /// Second layer: query word corpus based on user preference (moedict/wiki/news)
    func suggestWordCorpus(prefix: String, limit: Int = 5) -> [String] {
        let corpus = prefs.wordCorpus
        switch corpus {
        case "moedict":
            return phraseCompletions(for: prefix, limit: limit)
        case "news":
            return queryWBMM(data: wnData, keyCount: wnKeyCount, keyIndexOff: wnKeyIndexOff,
                             valIndexOff: wnValIndexOff, key: prefix, limit: limit)
        default: // "wiki"
            return suggestWordNgram(context: [prefix], limit: limit)
        }
    }

    // MARK: - Trigram query

    func suggestTrigram(prev2: String, prev1: String, limit: Int = 4) -> [String] {
        guard let d = tgData, tgKeyCount > 0,
              let s0 = prev2.unicodeScalars.first, let s1 = prev1.unicodeScalars.first else { return [] }
        let t0 = s0.value, t1 = s1.value
        var lo = 0, hi = tgKeyCount - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let off = tgKeysOff + mid * 8
            let k0 = d.u32(off), k1 = d.u32(off + 4)
            if k0 == t0 && k1 == t1 { return readTgValues(d, at: mid, limit: limit) }
            else if k0 < t0 || (k0 == t0 && k1 < t1) { lo = mid + 1 }
            else { hi = mid - 1 }
        }
        return []
    }

    private func readTgValues(_ d: Data, at idx: Int, limit: Int) -> [String] {
        let valOff = Int(d.u32(tgOffsetsOff + idx * 4))
        let count = min(Int(d.u16(tgCountsOff + idx * 2)), limit)
        var r: [String] = []
        for i in 0..<count {
            let off = tgValuesOff + (valOff + i) * 4
            guard off + 4 <= d.count else { break }
            if let s = Unicode.Scalar(d.u32(off)) { r.append(String(s)) }
        }
        return r
    }

    // MARK: - NER / Phrase queries

    func suggestPhrases(after char: String, limit: Int = 4) -> [String] {
        guard let d = nerData, nerKeyCount > 0,
              let s = char.unicodeScalars.first else { return [] }
        let target = s.value
        var lo = 0, hi = nerKeyCount - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let k = d.u32(nerKeysOff + mid * 4)
            if k == target { return readPhrases(d, keysOff: nerKeysOff, offsetsOff: nerOffsetsOff,
                                                countsOff: nerCountsOff, phrasesOff: nerPhrasesOff, at: mid, limit: limit) }
            else if k < target { lo = mid + 1 } else { hi = mid - 1 }
        }
        return []
    }

    func phraseCompletions(for prefix: String, limit: Int = 3) -> [String] {
        guard prefix.count >= 2, let first = prefix.first else { return [] }
        var results: [String] = []
        for phrase in phraseLookup(char: String(first), limit: 30) {
            if phrase.hasPrefix(prefix) && phrase.count > prefix.count {
                results.append(String(phrase.dropFirst(prefix.count)))
                if results.count >= limit { break }
            }
        }
        return results
    }

    /// Given a prefix (e.g. "馬達"), return completions (e.g. "加斯加")
    func completions(for prefix: String, limit: Int = 3) -> [String] {
        guard prefix.count >= 2, let first = prefix.first else { return [] }
        // Search both NER and phrase dictionary
        var results: [String] = []
        var seen = Set<String>()

        // Phrase dictionary first (broader coverage)
        for phrase in phraseLookup(char: String(first), limit: 30) {
            if phrase.hasPrefix(prefix) && phrase.count > prefix.count {
                let remainder = String(phrase.dropFirst(prefix.count))
                if seen.insert(remainder).inserted { results.append(remainder) }
                if results.count >= limit { return results }
            }
        }

        // Then NER
        let all = suggestPhrases(after: String(first), limit: 20)
        for phrase in all {
            if phrase.hasPrefix(prefix) && phrase.count > prefix.count {
                let remainder = String(phrase.dropFirst(prefix.count))
                if seen.insert(remainder).inserted { results.append(remainder) }
                if results.count >= limit { break }
            }
        }
        return results
    }

    private func phraseLookup(char: String, limit: Int = 30) -> [String] {
        guard let d = phData, phKeyCount > 0,
              let s = char.unicodeScalars.first else { return [] }
        let target = s.value
        var lo = 0, hi = phKeyCount - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let k = d.u32(phKeysOff + mid * 4)
            if k == target { return readPhrases(d, keysOff: phKeysOff, offsetsOff: phOffsetsOff,
                                                countsOff: phCountsOff, phrasesOff: phPhrasesOff, at: mid, limit: limit) }
            else if k < target { lo = mid + 1 } else { hi = mid - 1 }
        }
        return []
    }

    private func readPhrases(_ d: Data, keysOff: Int, offsetsOff: Int,
                             countsOff: Int, phrasesOff: Int, at idx: Int, limit: Int) -> [String] {
        var pos = phrasesOff + Int(d.u32(offsetsOff + idx * 4))
        let count = min(Int(d.u16(countsOff + idx * 2)), limit)
        var r: [String] = []
        for _ in 0..<count {
            guard pos >= 0, pos < d.count else { break }
            let len = Int(d[pos]); pos += 1
            guard pos + len * 4 <= d.count else { break }
            var s = ""
            for _ in 0..<len {
                if let sc = Unicode.Scalar(d.u32(pos)) { s.append(Character(sc)) }
                pos += 4
            }
            r.append(s)
        }
        return r
    }

    // MARK: - Word n-gram / Chengyu

    func suggestWordNgram(context: [String], limit: Int = 3) -> [String] {
        if context.count >= 2 {
            let key3 = context[context.count - 2] + "\t" + context[context.count - 1]
            let r = queryWBMM(data: wbData, keyCount: wbKeyCount, keyIndexOff: wbKeyIndexOff,
                              valIndexOff: wbValIndexOff, key: key3, limit: limit)
            if !r.isEmpty { return r }
        }
        if let last = context.last {
            return queryWBMM(data: wbData, keyCount: wbKeyCount, keyIndexOff: wbKeyIndexOff,
                             valIndexOff: wbValIndexOff, key: last, limit: limit)
        }
        return []
    }

    /// Backward compat
    func suggestWordBigram(after word: String, limit: Int = 3) -> [String] {
        return suggestWordNgram(context: [word], limit: limit)
    }

    func suggestChengyu(prefix: String, limit: Int = 3) -> [String] {
        queryWBMM(data: cyData, keyCount: cyKeyCount, keyIndexOff: cyKeyIndexOff,
                  valIndexOff: cyValIndexOff, key: prefix, limit: limit)
    }

    // MARK: - WBMM binary search

    private func queryWBMM(data d: Data?, keyCount: Int, keyIndexOff: Int,
                           valIndexOff: Int, key: String, limit: Int) -> [String] {
        guard let d = d, keyCount > 0 else { return [] }
        let target = Array(key.utf8)
        var lo = 0, hi = keyCount - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let entryOff = keyIndexOff + mid * 12
            guard entryOff + 12 <= d.count else { return [] }
            let strOff = Int(d.u32(entryOff))
            let strLen = Int(d.u16(entryOff + 4))
            guard strOff >= 0, strOff + strLen <= d.count else { return [] }
            let cmp = compareUTF8(d, off: strOff, len: strLen, with: target)
            if cmp == 0 {
                let valStart = Int(d.u32(entryOff + 6))
                let valCount = min(Int(d.u16(entryOff + 10)), limit)
                var r: [String] = []
                for i in 0..<valCount {
                    let vOff = valIndexOff + (valStart + i) * 6
                    guard vOff + 6 <= d.count else { break }
                    let vStrOff = Int(d.u32(vOff))
                    let vStrLen = Int(d.u16(vOff + 4))
                    guard vStrOff >= 0, vStrOff + vStrLen <= d.count else { continue }
                    if let s = String(data: d[vStrOff..<(vStrOff + vStrLen)], encoding: .utf8) { r.append(s) }
                }
                return r
            } else if cmp < 0 { lo = mid + 1 } else { hi = mid - 1 }
        }
        return []
    }

    private func compareUTF8(_ d: Data, off: Int, len: Int, with target: [UInt8]) -> Int {
        let n = min(len, target.count)
        for i in 0..<n {
            guard off + i < d.count else { return -1 }
            let a = d[off + i], b = target[i]
            if a != b { return a < b ? -1 : 1 }
        }
        return len < target.count ? -1 : (len > target.count ? 1 : 0)
    }
}

// MARK: - Data helpers
extension Data {
    func u32(_ off: Int) -> UInt32 {
        guard off >= 0, off + 4 <= count else { return 0 }
        return withUnsafeBytes { $0.load(fromByteOffset: off, as: UInt32.self).littleEndian }
    }
    func u16(_ off: Int) -> UInt16 {
        guard off >= 0, off + 2 <= count else { return 0 }
        return withUnsafeBytes { $0.load(fromByteOffset: off, as: UInt16.self).littleEndian }
    }
}
