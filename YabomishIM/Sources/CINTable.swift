import Foundation

/// Unified CIN table — mmap binary reader (.bin via CINCompiler) + text .cin fallback.
/// Binary path: liu.bin loaded via mappedIfSafe (zero-copy). Text path: parse .cin into Dict.
final class CINTable {
    // MARK: - mmap binary (liu.bin)
    private var binData: Data?
    private var entryCount = 0
    private var codesOff = 0
    private var valsOff = 0
    private var stringsOff = 0
    private var charsOff = 0

    // MARK: - Text fallback + overlay (extras, emoji — small Dict)
    private var overlay: [String: [String]] = [:]

    // MARK: - Reverse lookup caches (lazy, released on memory pressure)
    private var _reverseTable: [String: [String]]?
    private var reverseTable: [String: [String]] {
        if let cached = _reverseTable { return cached }
        guard MemoryBudget.canAfford(MemoryBudget.reverseTable) else { return [:] }
        var r: [String: [String]] = [:]
        if let d = binData {
            for i in 0..<entryCount {
                let code = readCode(d, at: i)
                for ch in readChars(d, at: i) { r[ch, default: []].append(code) }
            }
        }
        for (code, chars) in overlay { for c in chars { r[c, default: []].append(code) } }
        _reverseTable = r
        return r
    }

    private var _shortestCodes: [String: Set<String>]?
    var shortestCodesTable: [String: Set<String>] {
        if let cached = _shortestCodes { return cached }
        var r: [String: Set<String>] = [:]
        for (char, codes) in reverseTable {
            let m = codes.min(by: { $0.count < $1.count })?.count ?? 0
            r[char] = Set(codes.filter { $0.count == m })
        }
        _shortestCodes = r; return r
    }

    private var _longestCodes: [String: Set<String>]?
    var longestCodesTable: [String: Set<String>] {
        if let cached = _longestCodes { return cached }
        var r: [String: Set<String>] = [:]
        for (char, codes) in reverseTable {
            let m = codes.max(by: { $0.count < $1.count })?.count ?? 0
            r[char] = Set(codes.filter { $0.count == m })
        }
        _longestCodes = r; return r
    }

    private(set) var t2s: [String: String] = [:]
    private(set) var s2t: [String: String] = [:]
    private(set) var selKeys: [Character] = Array("1234567890")
    private(set) var cinName: String = ""
    var isEmpty: Bool { entryCount == 0 && overlay.isEmpty }
    private(set) var maxCodeLength: Int = 4

    func releaseOptionalCaches() {
        _reverseTable = nil
        _shortestCodes = nil
        _longestCodes = nil
    }

    // MARK: - Load

    func reload() {
        binData = nil; entryCount = 0; overlay = [:]
        _reverseTable = nil; _shortestCodes = nil; _longestCodes = nil
        t2s = [:]; s2t = [:]

        // 1. Try mmap binary from shared dir
        let userBin = AppConstants.sharedDir + "/liu.bin"
        if FileManager.default.fileExists(atPath: userBin) {
            loadBin(path: userBin)
        }
        // 2. If no .bin, try compiling .cin → .bin on the fly
        if entryCount == 0 {
            let cinPath = AppConstants.cinPath
            if FileManager.default.fileExists(atPath: cinPath) {
                CINCompiler.compile(src: cinPath, dst: userBin)
                if FileManager.default.fileExists(atPath: userBin) { loadBin(path: userBin) }
                // Compile failed, try text fallback
                if entryCount == 0 { parseCINIntoOverlay(path: cinPath) }
            }
        }
        // 3. Extras
        loadExtras()
        // 4. Char maps
        loadCharMaps()
        // 5. maxCodeLength
        maxCodeLength = 4
        if let d = binData {
            for i in 0..<entryCount {
                let len = Int(d.u16(codesOff + i * 6 + 4))
                if len > maxCodeLength { maxCodeLength = len }
            }
        }
        for k in overlay.keys { if k.count > maxCodeLength { maxCodeLength = k.count } }
        NSLog("YabomishIM: maxCodeLength = %d", maxCodeLength)
    }

    /// Load from a .cin text file (compiles to temp .bin first). For tests and on-the-fly use.
    func load(cinPath: String) {
        let tmp = NSTemporaryDirectory() + "cin_\(UUID().uuidString).bin"
        CINCompiler.compile(src: cinPath, dst: tmp)
        binData = nil; entryCount = 0; overlay = [:]
        _reverseTable = nil; _shortestCodes = nil; _longestCodes = nil
        if let d = try? Data(contentsOf: URL(fileURLWithPath: tmp)) {
            try? FileManager.default.removeItem(atPath: tmp)
            parseBinData(d)
        }
        // If compile failed, fall back to text parse
        if entryCount == 0 {
            parseCINIntoOverlay(path: cinPath)
        }
        maxCodeLength = 4
        if let d = binData {
            for i in 0..<entryCount {
                let len = Int(d.u16(codesOff + i * 6 + 4))
                if len > maxCodeLength { maxCodeLength = len }
            }
        }
        for k in overlay.keys { if k.count > maxCodeLength { maxCodeLength = k.count } }
    }

    /// Load from a .cin text file directly (macOS legacy path, also used by reload fallback).
    func load(path: String) {
        binData = nil; entryCount = 0; overlay = [:]
        _reverseTable = nil; _shortestCodes = nil; _longestCodes = nil
        // Try compile to bin first
        let tmp = NSTemporaryDirectory() + "cin_\(UUID().uuidString).bin"
        CINCompiler.compile(src: path, dst: tmp)
        if let d = try? Data(contentsOf: URL(fileURLWithPath: tmp)) {
            try? FileManager.default.removeItem(atPath: tmp)
            parseBinData(d)
        }
        if entryCount == 0 {
            parseCINIntoOverlay(path: path)
        }
        loadCharMaps()
        maxCodeLength = 4
        if let d = binData {
            for i in 0..<entryCount {
                let len = Int(d.u16(codesOff + i * 6 + 4))
                if len > maxCodeLength { maxCodeLength = len }
            }
        }
        for k in overlay.keys { if k.count > maxCodeLength { maxCodeLength = k.count } }
        NSLog("YabomishIM: Loaded %d bin entries + %d overlay entries from %@", entryCount, overlay.count, path)
    }

    // MARK: - Binary loading

    private func loadBin(path: String) {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              d.count >= 128,
              d[0] == 0x43, d[1] == 0x49, d[2] == 0x4E, d[3] == 0x4D else { return }
        parseBinHeader(d)
        binData = d
    }

    private func parseBinData(_ d: Data) {
        guard d.count >= 128,
              d[0] == 0x43, d[1] == 0x49, d[2] == 0x4E, d[3] == 0x4D else { return }
        parseBinHeader(d)
        binData = d
    }

    private func parseBinHeader(_ d: Data) {
        entryCount = Int(d.u32(4))
        let skLen = Int(d[8])
        if skLen > 0, 9 + skLen <= d.count { selKeys = (0..<skLen).map { Character(UnicodeScalar(d[9 + $0])) } }
        let cnLen = Int(d.u16(20))
        if cnLen > 0, 22 + cnLen <= d.count, let s = String(data: d[22..<(22+cnLen)], encoding: .utf8) { cinName = s }
        codesOff = Int(d.u32(96))
        valsOff = Int(d.u32(100))
        stringsOff = Int(d.u32(104))
        charsOff = Int(d.u32(108))
        guard codesOff <= d.count, valsOff <= d.count, stringsOff <= d.count, charsOff <= d.count else {
            entryCount = 0; return
        }
    }

    // MARK: - Binary helpers

    @inline(__always) private func readCode(_ d: Data, at i: Int) -> String {
        let off = Int(d.u32(codesOff + i * 6))
        let len = Int(d.u16(codesOff + i * 6 + 4))
        let start = stringsOff + off
        guard start >= 0, start + len <= d.count else { return "" }
        return String(data: d[start..<(start + len)], encoding: .ascii) ?? ""
    }

    @inline(__always) private func readChars(_ d: Data, at i: Int) -> [String] {
        let entryOff = valsOff + i * 4
        guard entryOff + 3 <= d.count else { return [] }
        let vOff = Int(d.u16(entryOff))
        let vCnt = Int(d[entryOff + 2])
        var r: [String] = []
        r.reserveCapacity(vCnt)
        for j in 0..<vCnt {
            let off = charsOff + (vOff + j) * 4
            guard off + 4 <= d.count else { break }
            let cp = d.u32(off)
            if let s = Unicode.Scalar(cp) { r.append(String(s)) }
        }
        return r
    }

    private func binSearch(_ code: String) -> Int {
        guard let d = binData, entryCount > 0 else { return -1 }
        let target = code.utf8
        var lo = 0, hi = entryCount - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let cmp = compareCode(d, at: mid, with: target)
            if cmp == 0 { return mid }
            else if cmp < 0 { lo = mid + 1 }
            else { hi = mid - 1 }
        }
        return -1
    }

    private func lowerBound(_ prefix: String) -> Int {
        guard let d = binData, entryCount > 0 else { return 0 }
        let target = prefix.utf8
        var lo = 0, hi = entryCount
        while lo < hi {
            let mid = (lo + hi) / 2
            if comparePrefixCode(d, at: mid, with: target) < 0 { lo = mid + 1 }
            else { hi = mid }
        }
        return lo
    }

    @inline(__always) private func compareCode(_ d: Data, at i: Int, with target: String.UTF8View) -> Int {
        let off = stringsOff + Int(d.u32(codesOff + i * 6))
        let len = Int(d.u16(codesOff + i * 6 + 4))
        guard off >= 0, off + len <= d.count else { return -1 }
        var ti = target.startIndex
        for j in 0..<len {
            if ti == target.endIndex { return 1 }
            let a = d[off + j], b = target[ti]
            if a != b { return Int(a) - Int(b) }
            ti = target.index(after: ti)
        }
        if ti != target.endIndex { return -1 }
        return 0
    }

    @inline(__always) private func comparePrefixCode(_ d: Data, at i: Int, with prefix: String.UTF8View) -> Int {
        let off = stringsOff + Int(d.u32(codesOff + i * 6))
        let len = Int(d.u16(codesOff + i * 6 + 4))
        guard off >= 0, off + len <= d.count else { return -1 }
        var ti = prefix.startIndex
        for j in 0..<min(len, prefix.count) {
            if ti == prefix.endIndex { return 0 }
            let a = d[off + j], b = prefix[ti]
            if a != b { return Int(a) - Int(b) }
            ti = prefix.index(after: ti)
        }
        if len < prefix.count { return -1 }
        return 0
    }

    @inline(__always) private func codeHasPrefix(_ d: Data, at i: Int, _ prefix: String.UTF8View) -> Bool {
        let off = stringsOff + Int(d.u32(codesOff + i * 6))
        let len = Int(d.u16(codesOff + i * 6 + 4))
        guard off >= 0, off + len <= d.count else { return false }
        guard len >= prefix.count else { return false }
        var ti = prefix.startIndex
        for j in 0..<prefix.count {
            if d[off + j] != prefix[ti] { return false }
            ti = prefix.index(after: ti)
        }
        return true
    }

    // MARK: - Text CIN parser (fallback + overlay)

    private func parseCINIntoOverlay(path: String) {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return }
        var inChardef = false
        content.enumerateLines { line, _ in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("%selkey ") {
                let keys = String(t.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                if !keys.isEmpty { self.selKeys = Array(keys) }; return
            }
            if t.hasPrefix("%cname ") {
                self.cinName = String(t.dropFirst(7)).trimmingCharacters(in: .whitespaces); return
            }
            if t == "%chardef begin" { inChardef = true; return }
            if t == "%chardef end" { inChardef = false; return }
            guard inChardef else { return }
            let parts: [String]
            if t.contains("\t") { parts = t.split(separator: "\t", maxSplits: 1).map(String.init) }
            else { parts = t.split(separator: " ", maxSplits: 1).map(String.init) }
            guard parts.count == 2 else { return }
            let code = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            self.overlay[code, default: []].append(value)
        }
    }

    // MARK: - Extras + char maps

    private func loadExtras() {
        let dir = AppConstants.tablesDir
        #if os(macOS)
        var dirs = [dir, NSHomeDirectory() + "/Library/YabomishIM/tables"]
        if let sync = YabomishPrefs.syncFolder {
            dirs.append((sync as NSString).appendingPathComponent("tables"))
        }
        for d in dirs {
            loadTablesFromDir(d)
        }
        #else
        loadTablesFromDir(dir)
        #endif
    }

    private func loadTablesFromDir(_ dir: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for file in files where file.hasSuffix(".txt") {
            let path = dir + "/" + file
            guard let data = FileManager.default.contents(atPath: path),
                  let content = String(data: data, encoding: .utf8) else { continue }
            content.enumerateLines { line, _ in
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return }
                let code = parts[0].lowercased()
                self.overlay[code, default: []].append(parts[1])
            }
        }
    }

    private func loadCharMaps() {
        let sharedDir = AppConstants.sharedDir + "/"
        let bundlePath = (Bundle.main.resourcePath ?? "") + "/"
        for (name, kp) in [("t2s", \CINTable.t2s), ("s2t", \CINTable.s2t)] {
            let shared = sharedDir + name + ".json"
            let bundled = bundlePath + name + ".json"
            let p = FileManager.default.fileExists(atPath: shared) ? shared : bundled
            guard let data = FileManager.default.contents(atPath: p),
                  let map = try? JSONDecoder().decode([String: String].self, from: data) else { continue }
            self[keyPath: kp] = map
        }
    }

    // MARK: - Lookup (public API)

    func lookup(_ code: String) -> [String] {
        let c = code.lowercased()
        var result: [String] = []
        let idx = binSearch(c)
        if idx >= 0, let d = binData { result = readChars(d, at: idx) }
        if let extra = overlay[c] { result += extra }
        return result
    }

    func hasPrefix(_ prefix: String) -> Bool {
        let p = prefix.lowercased()
        // Binary: check via binary search
        if let d = binData {
            let i = lowerBound(p)
            if i < entryCount && codeHasPrefix(d, at: i, p.utf8) { return true }
        }
        // Overlay: scan keys
        return overlay.keys.contains { $0.hasPrefix(p) }
    }

    func validNextKeys(after prefix: String) -> Set<Character> {
        let p = prefix.lowercased()
        var result = Set<Character>()
        let pLen = p.utf8.count
        // Binary: scan from lowerBound
        if let d = binData {
            let start = lowerBound(p)
            for i in start..<entryCount {
                guard codeHasPrefix(d, at: i, p.utf8) else { break }
                let codeLen = Int(d.u16(codesOff + i * 6 + 4))
                if codeLen > pLen {
                    let off = stringsOff + Int(d.u32(codesOff + i * 6))
                    guard off + pLen < d.count else { continue }
                    result.insert(Character(UnicodeScalar(d[off + pLen])))
                }
            }
        }
        // Overlay
        for key in overlay.keys where key.hasPrefix(p) && key.count > p.count {
            result.insert(key[key.index(key.startIndex, offsetBy: p.count)])
        }
        return result
    }

    func wildcardLookup(_ pattern: String) -> [String] {
        let pat = pattern.lowercased()
        guard pat.contains("*") else { return lookup(pat) }
        let regex = "^" + NSRegularExpression.escapedPattern(for: pat)
            .replacingOccurrences(of: "\\*", with: ".+") + "$"
        guard let re = try? NSRegularExpression(pattern: regex) else { return [] }
        let fix = String(pat.prefix(while: { $0 != "*" }))
        var results: [String] = []; var seen = Set<String>()
        // Binary
        if let d = binData {
            let start = fix.isEmpty ? 0 : lowerBound(fix)
            for i in start..<entryCount {
                if !fix.isEmpty && !codeHasPrefix(d, at: i, fix.utf8) { break }
                let code = readCode(d, at: i)
                if re.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil {
                    for c in readChars(d, at: i) where seen.insert(c).inserted { results.append(c) }
                }
            }
        }
        // Overlay
        for (code, chars) in overlay {
            guard fix.isEmpty || code.hasPrefix(fix) else { continue }
            if re.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil {
                for c in chars where seen.insert(c).inserted { results.append(c) }
            }
        }
        return results
    }

    func reverseLookup(_ char: String) -> [String] { reverseTable[char] ?? [] }
    func convert(_ char: String, map: [String: String]) -> String { map[char] ?? char }
}
