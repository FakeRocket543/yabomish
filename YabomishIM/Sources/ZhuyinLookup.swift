import Foundation

/// 同音字查詢：字 → 注音 → 同音字（按字頻排序）
final class ZhuyinLookup {
    static let shared = ZhuyinLookup()

    private var charToZhuyins: [String: [String]] = [:]
    private var zhuyinToChars: [String: [String]] = [:]
    private var pinyinToChars: [String: [String]] = [:]
    private var charFreq: [String: Int] = [:]
    private var bigramBoostData: Data?  // mmap'd BGBT binary
    private var bigramBoostCount: Int = 0
    private var bigramSuggest: [String: [String]] = [:]
    private var trigramSuggest: [String: [String]] = [:]
    private var loaded = false
    private let loadLock = NSLock()

    private init() {}

    /// 背景預熱：在非主線程呼叫，提前載入所有資料
    func warmup() { ensureLoaded() }

    /// Resolve data file: AppConstants.sharedDir → Bundle fallback
    private func dataPath(_ name: String, _ ext: String) -> String? {
        let shared = AppConstants.sharedDir + "/\(name).\(ext)"
        if FileManager.default.fileExists(atPath: shared) { return shared }
        return Bundle.main.path(forResource: name, ofType: ext)
    }

    private func ensureLoaded() {
        loadLock.lock()
        defer { loadLock.unlock() }
        guard !loaded else { return }
        guard MemoryBudget.canAfford(MemoryBudget.zhuyinLookup) else { return }
        loaded = true

        guard let p = dataPath("zhuyin_data", "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: p)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let z2c = json["zhuyin_to_chars"] as? [String: [String]],
              let c2z = json["char_to_zhuyins"] as? [String: [String]] else {
            NSLog("YabomishIM: zhuyin_data.json not found")
            return
        }
        zhuyinToChars = z2c; charToZhuyins = c2z

        if let fp = dataPath("char_freq", "json"),
           let fd = try? Data(contentsOf: URL(fileURLWithPath: fp)),
           let freq = try? JSONSerialization.jsonObject(with: fd) as? [String: Int] {
            charFreq = freq
        }
        NSLog("YabomishIM: zhuyin loaded — %d readings, %d chars, %d freq", z2c.count, c2z.count, charFreq.count)

        if let pp = dataPath("pinyin_data", "json"),
           let pd = try? Data(contentsOf: URL(fileURLWithPath: pp)),
           let pj = try? JSONSerialization.jsonObject(with: pd) as? [String: Any],
           let p2c = pj["pinyin_to_chars"] as? [String: [String]] {
            pinyinToChars = p2c
        }

        // bigram_boost: prefer binary, fallback JSON
        if let bp = dataPath("bigram_boost", "bin"),
           let bd = try? Data(contentsOf: URL(fileURLWithPath: bp), options: .mappedIfSafe),
           bd.count >= 8, bd[0] == 0x42, bd[1] == 0x47, bd[2] == 0x42, bd[3] == 0x54 {
            bigramBoostData = bd
            bigramBoostCount = Int(bd.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self).littleEndian })
            NSLog("YabomishIM: bigram_boost.bin loaded — %d entries (mmap)", bigramBoostCount)
        } else if let bp = dataPath("bigram_boost", "json"),
           let bd = try? Data(contentsOf: URL(fileURLWithPath: bp)),
           let bj = try? JSONSerialization.jsonObject(with: bd) as? [String: [String: [[Any]]]] {
            // Legacy JSON fallback — build index in memory
            var count = 0
            for (_, inner) in bj { count += inner.count }
            NSLog("YabomishIM: bigram_boost.json loaded — %d entries (legacy)", count)
        }

        if let sp = dataPath("bigram_suggest", "json"),
           let sd = try? Data(contentsOf: URL(fileURLWithPath: sp)),
           let sj = try? JSONSerialization.jsonObject(with: sd) as? [String: [String]] {
            bigramSuggest = sj
        }

        if let tp = dataPath("trigram_suggest", "json"),
           let td = try? Data(contentsOf: URL(fileURLWithPath: tp)),
           let tj = try? JSONSerialization.jsonObject(with: td) as? [String: [String]] {
            trigramSuggest = tj
        }
    }

    // MARK: - Sort

    func sortByFreq(_ chars: [String]) -> [String] {
        ensureLoaded()
        return chars.sorted { (charFreq[$0] ?? 0) > (charFreq[$1] ?? 0) }
    }

    func sortByFreq(_ chars: [String], prevChar: String?, curZhuyin: String) -> [String] {
        return sortByFreq(chars, prevChar: prevChar)
    }

    /// Non-optional prevChar overload (used by InputEngine via former stub)
    func sortByFreq(_ chars: [String], prevChar: String, curZhuyin: String) -> [String] {
        return sortByFreq(chars, prevChar: prevChar)
    }

    func sortByFreq(_ chars: [String], prevChar: String?) -> [String] {
        ensureLoaded()
        guard let prev = prevChar,
              let prevZhuyins = charToZhuyins[prev],
              !prevZhuyins.isEmpty else {
            return sortByFreq(chars)
        }
        var boostMap: [String: Int] = [:]
        for ch in chars {
            guard let curZhuyins = charToZhuyins[ch] else { continue }
            for pzy in prevZhuyins {
                for czy in curZhuyins {
                    for (c, f) in queryBGBT(prevZy: pzy, curZy: czy) {
                        if c == ch { boostMap[ch] = max(boostMap[ch] ?? 0, f) }
                    }
                }
            }
        }
        if boostMap.isEmpty { return sortByFreq(chars) }
        let boosted = chars.filter { boostMap[$0] != nil }.sorted { (boostMap[$0] ?? 0) > (boostMap[$1] ?? 0) }
        let rest = chars.filter { boostMap[$0] == nil }.sorted { (charFreq[$0] ?? 0) > (charFreq[$1] ?? 0) }
        return boosted + rest
    }

    // MARK: - BGBT binary query

    /// Query bigram_boost binary for (prevZy, curZy) → [(char, freq)]
    private func queryBGBT(prevZy: String, curZy: String) -> [(String, Int)] {
        guard let d = bigramBoostData, bigramBoostCount > 0 else { return [] }
        let pzyUTF8 = Array(prevZy.utf8)
        let czyUTF8 = Array(curZy.utf8)
        // Linear scan index (600K entries, ~12MB index, fast enough with mmap)
        // Each index entry: 20 bytes at offset 8 + i*20
        return d.withUnsafeBytes { buf -> [(String, Int)] in
            let base = buf.baseAddress!
            for i in 0..<bigramBoostCount {
                let idx = 8 + i * 20
                let pOff = Int(buf.load(fromByteOffset: idx, as: UInt32.self).littleEndian)
                let pLen = Int(buf.load(fromByteOffset: idx + 4, as: UInt16.self).littleEndian)
                guard pLen == pzyUTF8.count else { continue }
                guard memcmp(base + pOff, pzyUTF8, pLen) == 0 else { continue }
                let cOff = Int(buf.load(fromByteOffset: idx + 6, as: UInt32.self).littleEndian)
                let cLen = Int(buf.load(fromByteOffset: idx + 10, as: UInt16.self).littleEndian)
                guard cLen == czyUTF8.count else { continue }
                guard memcmp(base + cOff, czyUTF8, cLen) == 0 else { continue }
                // Found match
                let pairsOff = Int(buf.load(fromByteOffset: idx + 12, as: UInt32.self).littleEndian)
                let pairsCount = Int(buf.load(fromByteOffset: idx + 16, as: UInt16.self).littleEndian)
                var result: [(String, Int)] = []
                for j in 0..<pairsCount {
                    let po = pairsOff + j * 8
                    let chOff = Int(buf.load(fromByteOffset: po, as: UInt32.self).littleEndian)
                    let chLen = Int(buf.load(fromByteOffset: po + 4, as: UInt16.self).littleEndian)
                    let freq = Int(buf.load(fromByteOffset: po + 6, as: UInt16.self).littleEndian)
                    if let s = String(bytes: UnsafeRawBufferPointer(start: base + chOff, count: chLen), encoding: .utf8) {
                        result.append((s, freq))
                    }
                }
                return result
            }
            return []
        }
    }

    // MARK: - Lookup

    func lookup(_ char: String, prevChar: String? = nil) -> [(zhuyin: String, chars: [String])] {
        ensureLoaded()
        guard let zhuyins = charToZhuyins[char] else { return [] }
        let all = zhuyins.compactMap { zy -> (zhuyin: String, chars: [String], freq: Int)? in
            guard let raw = zhuyinToChars[zy] else { return nil }
            let filtered = raw.filter { $0 != char }
            guard !filtered.isEmpty else { return nil }
            let sorted = (prevChar != nil) ? sortByFreq(filtered, prevChar: prevChar) : filtered
            let freq = filtered.reduce(0) { $0 + (charFreq[$1] ?? 0) }
            return (zy, sorted, freq)
        }.sorted { $0.freq > $1.freq }
        if YabomishPrefs.homophoneMultiReading {
            return all.map { ($0.zhuyin, $0.chars) }
        }
        guard let best = all.first else { return [] }
        return [(best.zhuyin, best.chars)]
    }

    // MARK: - Reverse lookup

    func charsForZhuyin(_ zhuyin: String) -> [String] {
        ensureLoaded()
        return zhuyinToChars[zhuyin] ?? []
    }

    func charsForZhuyin(_ zhuyin: String, prevChar: String?) -> [String] {
        ensureLoaded()
        let base = zhuyinToChars[zhuyin] ?? []
        guard let prev = prevChar,
              let prevZhuyins = charToZhuyins[prev],
              !prevZhuyins.isEmpty else { return base }
        var bestBoosts: [(String, Int)] = []
        for pzy in prevZhuyins {
            for (ch, freq) in queryBGBT(prevZy: pzy, curZy: zhuyin) {
                if freq > (bestBoosts.first(where: { $0.0 == ch })?.1 ?? 0) {
                    bestBoosts.removeAll { $0.0 == ch }
                    bestBoosts.append((ch, freq))
                }
            }
        }
        guard !bestBoosts.isEmpty else { return base }
        bestBoosts.sort { $0.1 > $1.1 }
        let boostChars = Set(bestBoosts.map { $0.0 })
        var result = bestBoosts.map { $0.0 }
        for ch in base where !boostChars.contains(ch) { result.append(ch) }
        return result
    }

    func charsForPinyin(_ pinyin: String) -> [String] {
        ensureLoaded()
        if let chars = pinyinToChars[pinyin], !chars.isEmpty { return chars }
        let converted = pinyin.replacingOccurrences(of: "v", with: "ü")
        if converted != pinyin, let chars = pinyinToChars[converted], !chars.isEmpty { return chars }
        return []
    }

    // MARK: - Suggest

    func suggestNext(after prev: String) -> [String] {
        ensureLoaded()
        guard let last = prev.last else { return [] }
        return bigramSuggest[String(last)] ?? []
    }

    func suggestNextTrigram(prev2: String) -> [String] {
        ensureLoaded()
        guard prev2.count >= 2 else { return [] }
        return trigramSuggest[String(prev2.suffix(2))] ?? []
    }
}
