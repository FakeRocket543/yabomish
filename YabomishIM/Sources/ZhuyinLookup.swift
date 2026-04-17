import Foundation

/// 同音字查詢：字 → 注音 → 同音字（按字頻排序）
final class ZhuyinLookup {
    static let shared = ZhuyinLookup()

    private var charToZhuyins: [String: [String]] = [:]
    private var zhuyinToChars: [String: [String]] = [:]
    private var pinyinToChars: [String: [String]] = [:]
    private var charFreq: [String: Int] = [:]
    private var loaded = false
    init() {}

    private func dataPath(_ name: String, _ ext: String) -> String? {
        let shared = AppConstants.sharedDir + "/\(name).\(ext)"
        if FileManager.default.fileExists(atPath: shared) { return shared }
        return Bundle.main.path(forResource: name, ofType: ext)
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        guard MemoryBudget.canAfford(MemoryBudget.zhuyinLookup) else { return }
        guard let p = dataPath("zhuyin_data", "json") else {
            DebugLog.log("ZhuyinLookup: zhuyin_data.json not found"); return
        }
        let data: Data
        do { data = try Data(contentsOf: URL(fileURLWithPath: p)) }
        catch { DebugLog.log("ZhuyinLookup read zhuyin_data: \(error.localizedDescription)"); return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let z2c = json["zhuyin_to_chars"] as? [String: [String]],
              let c2z = json["char_to_zhuyins"] as? [String: [String]] else {
            DebugLog.log("ZhuyinLookup: zhuyin_data.json parse failed"); return
        }
        zhuyinToChars = z2c; charToZhuyins = c2z
        loaded = true
        if let fp = dataPath("char_freq", "json") {
            do {
                let fd = try Data(contentsOf: URL(fileURLWithPath: fp))
                if let freq = (try? JSONSerialization.jsonObject(with: fd)) as? [String: Int] {
                    charFreq = freq
                } else {
                    DebugLog.log("ZhuyinLookup: char_freq.json parse failed")
                }
            } catch { DebugLog.log("ZhuyinLookup read char_freq: \(error.localizedDescription)") }
        }
        DebugLog.log("YabomishIM: zhuyin loaded — \(z2c.count) readings, \(c2z.count) chars, \(charFreq.count) freq")
        if let pp = dataPath("pinyin_data", "json") {
            do {
                let pd = try Data(contentsOf: URL(fileURLWithPath: pp))
                if let pj = try? JSONSerialization.jsonObject(with: pd) as? [String: Any],
                   let p2c = pj["pinyin_to_chars"] as? [String: [String]] { pinyinToChars = p2c }
            } catch { DebugLog.log("ZhuyinLookup read pinyin_data: \(error.localizedDescription)") }
        }
    }

    // MARK: - Sort

    func sortByFreq(_ chars: [String]) -> [String] {
        ensureLoaded()
        return chars.sorted { (charFreq[$0] ?? 0) > (charFreq[$1] ?? 0) }
    }

    /// Backward-compat overloads — prevChar no longer used after bigram removal
    func sortByFreq(_ chars: [String], prevChar: String?, curZhuyin: String) -> [String] { sortByFreq(chars) }
    func sortByFreq(_ chars: [String], prevChar: String, curZhuyin: String) -> [String] { sortByFreq(chars) }
    func sortByFreq(_ chars: [String], prevChar: String?) -> [String] { sortByFreq(chars) }

    // MARK: - Lookup

    func lookup(_ char: String) -> [(zhuyin: String, chars: [String])] {
        ensureLoaded()
        guard let zhuyins = charToZhuyins[char] else { return [] }
        // char_to_zhuyins 的順序 = 常用讀音在前，直接保留
        let all = zhuyins.compactMap { zy -> (zhuyin: String, chars: [String])? in
            guard let raw = zhuyinToChars[zy] else { return nil }
            let filtered = raw.filter { $0 != char }
            guard !filtered.isEmpty else { return nil }
            return (zy, filtered)
        }
        if YabomishPrefs.homophoneMultiReading {
            return all
        }
        guard let best = all.first else { return [] }
        return [best]
    }

    /// Backward-compat overload — prevChar no longer used
    func lookup(_ char: String, prevChar: String?) -> [(zhuyin: String, chars: [String])] { lookup(char) }

    // MARK: - Reverse lookup

    func charsForZhuyin(_ zhuyin: String) -> [String] {
        ensureLoaded()
        return zhuyinToChars[zhuyin] ?? []
    }

    /// Backward-compat overload — prevChar no longer used
    func charsForZhuyin(_ zhuyin: String, prevChar: String?) -> [String] { charsForZhuyin(zhuyin) }

    func charsForPinyin(_ pinyin: String) -> [String] {
        ensureLoaded()
        if let chars = pinyinToChars[pinyin], !chars.isEmpty { return chars }
        let converted = pinyin.replacingOccurrences(of: "v", with: "ü")
        if converted != pinyin, let chars = pinyinToChars[converted], !chars.isEmpty { return chars }
        return []
    }
}
