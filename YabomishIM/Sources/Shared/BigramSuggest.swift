import Foundation

/// Bigram-based next-character suggestion using mmap binary file.
/// Format: BGMM header + sorted UTF-32LE keys + offsets + counts + UTF-32LE values
final class BigramSuggest {
    static let shared = BigramSuggest()

    private var data: Data?
    private var keyCount = 0
    private var keysOffset = 0
    private var offsetsOffset = 0
    private var countsOffset = 0
    private var valuesOffset = 0

    init() {
        let shared = AppConstants.sharedDir + "/bigram.bin"
        let path = FileManager.default.fileExists(atPath: shared) ? shared
                 : Bundle.main.path(forResource: "bigram", ofType: "bin")
        guard let p = path,
              let d = try? Data(contentsOf: URL(fileURLWithPath: p), options: .mappedIfSafe),
              d.count >= 12, d[0] == 0x42, d[1] == 0x47, d[2] == 0x4D, d[3] == 0x4D else { return }
        keyCount = Int(d.u32(4))
        keysOffset = 8
        offsetsOffset = keysOffset + keyCount * 4
        countsOffset = offsetsOffset + keyCount * 4
        valuesOffset = countsOffset + keyCount * 2
        guard valuesOffset <= d.count else { return }
        data = d
    }

    func suggest(after prev: String, limit: Int = 6) -> [String] {
        guard let data, keyCount > 0,
              let scalar = prev.unicodeScalars.first else { return [] }
        let target = scalar.value
        var lo = 0, hi = keyCount - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let k = data.u32(keysOffset + mid * 4)
            if k == target {
                let valOff = Int(data.u32(offsetsOffset + mid * 4))
                let count = min(Int(data.u16(countsOffset + mid * 2)), limit)
                var r: [String] = []
                for i in 0..<count {
                    let off = valuesOffset + (valOff + i) * 4
                    guard off + 4 <= data.count else { break }
                    if let s = Unicode.Scalar(data.u32(off)) { r.append(String(s)) }
                }
                return r
            } else if k < target { lo = mid + 1 } else { hi = mid - 1 }
        }
        return []
    }
}
