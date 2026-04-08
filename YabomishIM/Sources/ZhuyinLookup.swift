import Foundation

/// 同音字查詢：字 → 注音 → 同音字（按字頻排序）
final class ZhuyinLookup {
    static let shared = ZhuyinLookup()

    private var charToZhuyins: [String: [String]] = [:]
    private var zhuyinToChars: [String: [String]] = [:]
    private var pinyinToChars: [String: [String]] = [:]
    private var charFreq: [String: Int] = [:]
    // bigram boost: prevZhuyin → curZhuyin → [(char, freq)]
    private var bigramBoost: [String: [String: [(String, Int)]]] = [:]
    /// Bigram suggest: prev_char → [next_char, ...]
    private var bigramSuggest: [String: [String]] = [:]
    /// Trigram suggest: prev2chars → [next_char, ...]
    private var trigramSuggest: [String: [String]] = [:]

    /// Resolve data file: ~/Library/Application Support/YabomishIM/ → Bundle fallback
    private func dataPath(_ name: String, _ ext: String) -> String? {
        let support = NSHomeDirectory() + "/Library/Application Support/YabomishIM/\(name).\(ext)"
        if FileManager.default.fileExists(atPath: support) { return support }
        return Bundle.main.path(forResource: name, ofType: ext)
    }

    private init() {
        let userPath = NSHomeDirectory() + "/Library/YabomishIM/zhuyin_data.json"
        let bundlePath = Bundle.main.path(forResource: "zhuyin_data", ofType: "json")
        let path = FileManager.default.fileExists(atPath: userPath) ? userPath : bundlePath

        guard let p = path, let data = try? Data(contentsOf: URL(fileURLWithPath: p)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let z2c = json["zhuyin_to_chars"] as? [String: [String]],
              let c2z = json["char_to_zhuyins"] as? [String: [String]]
        else {
            NSLog("YabomishIM: zhuyin_data.json not found")
            return
        }
        zhuyinToChars = z2c
        charToZhuyins = c2z

        // 載入萌典字頻
        if let fp = dataPath("char_freq", "json"),
           let fd = try? Data(contentsOf: URL(fileURLWithPath: fp)),
           let freq = try? JSONSerialization.jsonObject(with: fd) as? [String: Int] {
            charFreq = freq
        }
        NSLog("YabomishIM: zhuyin loaded — %d readings, %d chars, %d freq", z2c.count, c2z.count, charFreq.count)

        // 載入拼音表
        if let pp = Bundle.main.path(forResource: "pinyin_data", ofType: "json"),
           let pd = try? Data(contentsOf: URL(fileURLWithPath: pp)),
           let pj = try? JSONSerialization.jsonObject(with: pd) as? [String: Any],
           let p2c = pj["pinyin_to_chars"] as? [String: [String]] {
            pinyinToChars = p2c
            NSLog("YabomishIM: pinyin loaded — %d readings", p2c.count)
        }

        // 載入 bigram boost 表
        if let bp = dataPath("bigram_boost", "json"),
           let bd = try? Data(contentsOf: URL(fileURLWithPath: bp)),
           let bj = try? JSONSerialization.jsonObject(with: bd) as? [String: [String: [[Any]]]] {
            for (prevZy, inner) in bj {
                var innerDict: [String: [(String, Int)]] = [:]
                for (curZy, pairs) in inner {
                    innerDict[curZy] = pairs.compactMap { arr in
                        guard arr.count >= 2,
                              let ch = arr[0] as? String,
                              let freq = arr[1] as? Int else { return nil }
                        return (ch, freq)
                    }
                }
                bigramBoost[prevZy] = innerDict
            }
            NSLog("YabomishIM: bigram boost loaded — %d prev entries", bigramBoost.count)
        }

        // 載入 bigram suggest 表
        if let sp = dataPath("bigram_suggest", "json"),
           let sd = try? Data(contentsOf: URL(fileURLWithPath: sp)),
           let sj = try? JSONSerialization.jsonObject(with: sd) as? [String: [String]] {
            bigramSuggest = sj
            NSLog("YabomishIM: bigram suggest loaded — %d entries", sj.count)
        }

        // 載入 trigram suggest 表
        if let tp = dataPath("trigram_suggest", "json"),
           let td = try? Data(contentsOf: URL(fileURLWithPath: tp)),
           let tj = try? JSONSerialization.jsonObject(with: td) as? [String: [String]] {
            trigramSuggest = tj
            NSLog("YabomishIM: trigram suggest loaded — %d entries", tj.count)
        }
    }

    /// 依 zhuyin_data.json 的排序（已含一般字優先+字頻排序）
    func sortByFreq(_ chars: [String]) -> [String] {
        chars.sorted { (charFreq[$0] ?? 0) > (charFreq[$1] ?? 0) }
    }

    /// 帶上下文的排序：用前一個字做 bigram reranking
    func sortByFreq(_ chars: [String], prevChar: String?) -> [String] {
        guard let prev = prevChar,
              let prevZhuyins = charToZhuyins[prev],
              !prevZhuyins.isEmpty else {
            return sortByFreq(chars)
        }
        // 收集所有 boost
        var boostMap: [String: Int] = [:]
        for ch in chars {
            guard let curZhuyins = charToZhuyins[ch] else { continue }
            for pzy in prevZhuyins {
                for czy in curZhuyins {
                    if let pairs = bigramBoost[pzy]?[czy] {
                        for (c, f) in pairs where c == ch {
                            boostMap[ch] = max(boostMap[ch] ?? 0, f)
                        }
                    }
                }
            }
        }
        if boostMap.isEmpty { return sortByFreq(chars) }
        // boost 字排前面，其餘按字頻
        let boosted = chars.filter { boostMap[$0] != nil }.sorted { (boostMap[$0] ?? 0) > (boostMap[$1] ?? 0) }
        let rest = chars.filter { boostMap[$0] == nil }.sorted { (charFreq[$0] ?? 0) > (charFreq[$1] ?? 0) }
        return boosted + rest
    }

    /// 查同音字：輸入一個字，回傳 [(注音, [同音字])]
    /// prevChar: 前一個已確認的字（用於 bigram reranking）
    func lookup(_ char: String, prevChar: String? = nil) -> [(zhuyin: String, chars: [String])] {
        guard let zhuyins = charToZhuyins[char] else { return [] }
        let all = zhuyins.compactMap { zy -> (zhuyin: String, chars: [String], freq: Int)? in
            guard let raw = zhuyinToChars[zy] else { return nil }
            let filtered = raw.filter { $0 != char }
            guard !filtered.isEmpty else { return nil }
            // 用 bigram reranking 排序同音字
            let sorted = (prevChar != nil)
                ? sortByFreq(filtered, prevChar: prevChar)
                : filtered  // zhuyin_data.json 已排好序
            let freq = filtered.reduce(0) { $0 + (charFreq[$1] ?? 0) }
            return (zy, sorted, freq)
        }.sorted { $0.freq > $1.freq }
        if YabomishPrefs.homophoneMultiReading {
            return all.map { ($0.zhuyin, $0.chars) }
        }
        guard let best = all.first else { return [] }
        return [(best.zhuyin, best.chars)]
    }

    /// 注音反查：輸入注音，回傳對應的字（已按一般字優先+字頻排序）
    func charsForZhuyin(_ zhuyin: String) -> [String] {
        zhuyinToChars[zhuyin] ?? []
    }

    /// 注音反查（帶上下文）：用前一個字的注音做 bigram reranking
    /// prevChar: 前一個已確認的字（可為 nil）
    func charsForZhuyin(_ zhuyin: String, prevChar: String?) -> [String] {
        let base = zhuyinToChars[zhuyin] ?? []
        guard let prev = prevChar,
              let prevZhuyins = charToZhuyins[prev],
              !prevZhuyins.isEmpty else {
            return base
        }
        // 從前一個字的所有讀音中，找最佳 boost
        var bestBoosts: [(String, Int)] = []
        for pzy in prevZhuyins {
            if let pairs = bigramBoost[pzy]?[zhuyin] {
                for (ch, freq) in pairs {
                    if freq > (bestBoosts.first(where: { $0.0 == ch })?.1 ?? 0) {
                        bestBoosts.removeAll { $0.0 == ch }
                        bestBoosts.append((ch, freq))
                    }
                }
            }
        }
        guard !bestBoosts.isEmpty else { return base }
        // boost 字按頻率排前面，其餘照原排序
        bestBoosts.sort { $0.1 > $1.1 }
        let boostChars = Set(bestBoosts.map { $0.0 })
        var result = bestBoosts.map { $0.0 }
        for ch in base where !boostChars.contains(ch) {
            result.append(ch)
        }
        return result
    }

    /// 拼音反查：輸入拼音（如 "zhong1"），回傳對應的字
    /// 使用者輸入 v 代替 ü（如 lv4 = 綠）
    func charsForPinyin(_ pinyin: String) -> [String] {
        // 先直接查
        if let chars = pinyinToChars[pinyin], !chars.isEmpty { return chars }
        // v → ü 轉換（lv→lü, nv→nü）
        let converted = pinyin.replacingOccurrences(of: "v", with: "ü")
        if converted != pinyin, let chars = pinyinToChars[converted], !chars.isEmpty { return chars }
        return []
    }

    /// Bigram 聯想：輸入前一個字，回傳建議的下一個字
    func suggestNext(after prev: String) -> [String] {
        guard let last = prev.last else { return [] }
        return bigramSuggest[String(last)] ?? []
    }

    /// Trigram 聯想：輸入前兩個字，回傳建議的下一個字
    func suggestNextTrigram(prev2: String) -> [String] {
        guard prev2.count >= 2 else { return [] }
        let key = String(prev2.suffix(2))
        return trigramSuggest[key] ?? []
    }
}
