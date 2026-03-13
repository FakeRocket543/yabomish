import Foundation

/// 同音字查詢：字 → 注音 → 同音字（按字頻排序）
final class ZhuyinLookup {
    static let shared = ZhuyinLookup()

    private var charToZhuyins: [String: [String]] = [:]
    private var zhuyinToChars: [String: [String]] = [:]
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
    }

    /// 依萌典字頻排序（高頻在前，無頻率的排最後）
    func sortByFreq(_ chars: [String]) -> [String] {
        chars.sorted { (charFreq[$0] ?? 0) > (charFreq[$1] ?? 0) }
    }

    /// 查同音字：輸入一個字，回傳 [(注音, [同音字])]
    func lookup(_ char: String) -> [(zhuyin: String, chars: [String])] {
        guard let zhuyins = charToZhuyins[char] else { return [] }
        return zhuyins.compactMap { zy in
            guard let chars = zhuyinToChars[zy] else { return nil }
            // 排除自己
            let filtered = chars.filter { $0 != char }
            return filtered.isEmpty ? nil : (zy, filtered)
        }
    }

    /// 注音反查：輸入注音，回傳對應的字
    func charsForZhuyin(_ zhuyin: String) -> [String] {
        zhuyinToChars[zhuyin] ?? []
    }
}
