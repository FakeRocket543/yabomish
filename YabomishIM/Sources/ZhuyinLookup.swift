import Foundation

/// 同音字查詢：字 → 注音 → 同音字（按字頻排序）
final class ZhuyinLookup {
    static let shared = ZhuyinLookup()

    private var charToZhuyins: [String: [String]] = [:]
    private var zhuyinToChars: [String: [String]] = [:]
    private var pinyinToChars: [String: [String]] = [:]
    private var charFreq: [String: Int] = [:]

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
        if let fp = Bundle.main.path(forResource: "char_freq", ofType: "json"),
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
    }

    /// 依萌典字頻排序（高頻在前，無頻率的排最後）
    func sortByFreq(_ chars: [String]) -> [String] {
        chars.sorted { (charFreq[$0] ?? 0) > (charFreq[$1] ?? 0) }
    }

    /// 查同音字：輸入一個字，回傳 [(注音, [同音字])]，按同音字群字頻總和排序（常用讀音在前）
    /// homophoneMultiReading=false 時只回傳字頻最高的那組讀音
    func lookup(_ char: String) -> [(zhuyin: String, chars: [String])] {
        guard let zhuyins = charToZhuyins[char] else { return [] }
        let all = zhuyins.compactMap { zy -> (zhuyin: String, chars: [String], freq: Int)? in
            guard let chars = zhuyinToChars[zy] else { return nil }
            let filtered = chars.filter { $0 != char }
            guard !filtered.isEmpty else { return nil }
            let freq = filtered.reduce(0) { $0 + (charFreq[$1] ?? 0) }
            return (zy, filtered, freq)
        }.sorted { $0.freq > $1.freq }
        if YabomishPrefs.homophoneMultiReading {
            return all.map { ($0.zhuyin, $0.chars) }
        }
        // 預設只回傳最高頻的一組讀音
        guard let best = all.first else { return [] }
        return [(best.zhuyin, best.chars)]
    }

    /// 注音反查：輸入注音，回傳對應的字
    func charsForZhuyin(_ zhuyin: String) -> [String] {
        zhuyinToChars[zhuyin] ?? []
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
}
