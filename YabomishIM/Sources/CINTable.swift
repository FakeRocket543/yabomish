import Foundation

/// Unified CIN table — mmap binary reader (.bin via CINCompiler) + text .cin fallback.
/// Binary path: liu.bin loaded via mappedIfSafe (zero-copy). Text path: parse .cin into Dict.
///
/// 執行緒安全：所有可變狀態（binData/entryCount/offsets/overlay/反向快取/
/// t2s/s2t/selKeys/cinName/maxCodeLength）會被主執行緒的查詢熱路徑與背景
/// reload／預熱執行緒同時存取，統一由單一 NSLock（stateLock）保護。
/// 慣例：每個公開方法進入時經 locked {} 取得鎖一次；內部 helper 一律假設
/// 「已持鎖」，且不得在鎖內呼叫其他公開方法（避免 NSLock 不可重入導致死鎖）。
final class CINTable {
    // MARK: - 同步

    private let stateLock = NSLock()

    /// 在鎖內執行 body（查詢熱路徑每次只取得鎖一次，寫入罕見）
    private func locked<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    // MARK: - mmap binary (liu.bin) — 以下狀態一律在持鎖下存取
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
    /// 建構／讀取反向表（須持鎖；shortest/longest/reverseLookup 共用）
    private var reverseTableLocked: [String: [String]] {
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
        locked {
            if let cached = _shortestCodes { return cached }
            var r: [String: Set<String>] = [:]
            for (char, codes) in reverseTableLocked {
                let m = codes.min(by: { $0.count < $1.count })?.count ?? 0
                r[char] = Set(codes.filter { $0.count == m })
            }
            _shortestCodes = r; return r
        }
    }

    private var _longestCodes: [String: Set<String>]?
    var longestCodesTable: [String: Set<String>] {
        locked {
            if let cached = _longestCodes { return cached }
            var r: [String: Set<String>] = [:]
            for (char, codes) in reverseTableLocked {
                let m = codes.max(by: { $0.count < $1.count })?.count ?? 0
                r[char] = Set(codes.filter { $0.count == m })
            }
            _longestCodes = r; return r
        }
    }

    // 對外公開的唯讀屬性改為鎖內讀取的 computed property，內部寫入直接動 private 儲存區
    private var _t2s: [String: String] = [:]
    var t2s: [String: String] { locked { _t2s } }
    private var _s2t: [String: String] = [:]
    var s2t: [String: String] { locked { _s2t } }
    private var _selKeys: [Character] = Array("1234567890")
    var selKeys: [Character] { locked { _selKeys } }
    private var _cinName: String = ""
    var cinName: String { locked { _cinName } }
    var isEmpty: Bool { locked { entryCount == 0 && overlay.isEmpty } }
    private var _maxCodeLength: Int = 4
    var maxCodeLength: Int { locked { _maxCodeLength } }

    // MARK: - Load

    func reload() {
        // 鎖外先確保編譯快取新鮮（必要時重編整份 .cin，秒級 I/O），
        // 避免重載期間以鎖阻塞每鍵的 lookup 熱路徑
        Self.ensureFreshCompiledBin()
        locked {
            reloadLocked()
        }
    }

    /// 確保 sharedDir/liu.bin 比 liu.cin 新（mtime 檢查）；過舊或缺檔時重編。
    /// 必須在鎖外呼叫（編譯是長 I/O）；並發重編為冪等操作，可接受。
    private static func ensureFreshCompiledBin() {
        let fm = FileManager.default
        let cinPath = AppConstants.cinPath
        let userBin = AppConstants.sharedDir + "/liu.bin"
        guard fm.fileExists(atPath: cinPath) else { return }
        let binDate = (try? fm.attributesOfItem(atPath: userBin))?[.modificationDate] as? Date
        let cinDate = (try? fm.attributesOfItem(atPath: cinPath))?[.modificationDate] as? Date
        if let binDate, let cinDate, binDate >= cinDate { return }
        CINCompiler.compile(src: cinPath, dst: userBin)
    }

    /// reload 本體（須持鎖）
    private func reloadLocked() {
        binData = nil; entryCount = 0; overlay = [:]
        _reverseTable = nil; _shortestCodes = nil; _longestCodes = nil
        _t2s = [:]; _s2t = [:]

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
        _maxCodeLength = 4
        if let d = binData {
            for i in 0..<entryCount {
                let len = Int(d.u16(codesOff + i * 6 + 4))
                if len > _maxCodeLength { _maxCodeLength = len }
            }
        }
        for k in overlay.keys { if k.count > _maxCodeLength { _maxCodeLength = k.count } }
        DebugLog.log("YabomishIM: maxCodeLength = \(_maxCodeLength)")
    }

    /// Load from a .cin text file (compiles to temp .bin first). For tests and on-the-fly use.
    func load(cinPath: String) {
        locked {
            loadLocked(cinPath: cinPath)
        }
    }

    /// load(cinPath:) 本體（須持鎖）
    private func loadLocked(cinPath: String) {
        let tmp = NSTemporaryDirectory() + "cin_\(UUID().uuidString).bin"
        CINCompiler.compile(src: cinPath, dst: tmp)
        binData = nil; entryCount = 0; overlay = [:]
        _reverseTable = nil; _shortestCodes = nil; _longestCodes = nil
        _maxCodeLength = 4
        do {
            let d = try Data(contentsOf: URL(fileURLWithPath: tmp))
            try? FileManager.default.removeItem(atPath: tmp)
            parseBinData(d)
        } catch { DebugLog.log("CINTable load(cinPath:) read tmp: \(error.localizedDescription)") }
        // If compile failed, fall back to text parse
        if entryCount == 0 {
            parseCINIntoOverlay(path: cinPath)
        }
        if let d = binData {
            for i in 0..<entryCount {
                let len = Int(d.u16(codesOff + i * 6 + 4))
                if len > _maxCodeLength { _maxCodeLength = len }
            }
        }
        for k in overlay.keys { if k.count > _maxCodeLength { _maxCodeLength = k.count } }
    }

    /// Load from a .cin text file directly (macOS legacy path, also used by reload fallback).
    func load(path: String) {
        locked {
            loadLocked(path: path)
        }
    }

    /// load(path:) 本體（須持鎖）
    private func loadLocked(path: String) {
        binData = nil; entryCount = 0; overlay = [:]
        _reverseTable = nil; _shortestCodes = nil; _longestCodes = nil
        // Try compile to bin first
        let tmp = NSTemporaryDirectory() + "cin_\(UUID().uuidString).bin"
        CINCompiler.compile(src: path, dst: tmp)
        do {
            let d = try Data(contentsOf: URL(fileURLWithPath: tmp))
            try? FileManager.default.removeItem(atPath: tmp)
            parseBinData(d)
        } catch { DebugLog.log("CINTable load(path:) read tmp: \(error.localizedDescription)") }
        if entryCount == 0 {
            parseCINIntoOverlay(path: path)
        }
        loadCharMaps()
        _maxCodeLength = 4
        if let d = binData {
            for i in 0..<entryCount {
                let len = Int(d.u16(codesOff + i * 6 + 4))
                if len > _maxCodeLength { _maxCodeLength = len }
            }
        }
        for k in overlay.keys { if k.count > _maxCodeLength { _maxCodeLength = k.count } }
        DebugLog.log("YabomishIM: Loaded \(entryCount) bin entries + \(overlay.count) overlay entries from \(path)")
    }

    // MARK: - Binary loading

    private func loadBin(path: String) {
        let d: Data
        do { d = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) }
        catch { DebugLog.log("CINTable loadBin: \(error.localizedDescription)"); return }
        guard d.count >= 128,
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
        if skLen > 0, skLen <= 20, 9 + skLen <= d.count { _selKeys = (0..<skLen).map { Character(UnicodeScalar(d[9 + $0])) } }
        let cnLen = Int(d.u16(20))
        if cnLen > 0, 22 + cnLen <= d.count, let s = String(data: d[22..<(22+cnLen)], encoding: .utf8) { _cinName = s }
        codesOff = Int(d.u32(96))
        valsOff = Int(d.u32(100))
        stringsOff = Int(d.u32(104))
        charsOff = Int(d.u32(108))
        guard codesOff >= 128, codesOff < valsOff, valsOff < stringsOff, stringsOff < charsOff, charsOff <= d.count else {
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
        guard entryOff >= 0, entryOff + 3 <= d.count else { return [] }
        let vOff = Int(d.u16(entryOff))
        let vCnt = Int(d[entryOff + 2])
        guard vCnt > 0 else { return [] }
        // Validate that all values fit within charsOff region
        let firstOff = charsOff + vOff * 4
        let lastOff = charsOff + (vOff + vCnt - 1) * 4 + 4
        guard firstOff >= charsOff, lastOff <= d.count else { return [] }
        var r: [String] = []
        r.reserveCapacity(vCnt)
        for j in 0..<vCnt {
            let off = charsOff + (vOff + j) * 4
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
        let idxOff = codesOff + i * 6
        guard idxOff >= 0, idxOff + 6 <= d.count else { return -1 }
        let off = stringsOff + Int(d.u32(idxOff))
        let len = Int(d.u16(idxOff + 4))
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
        let idxOff = codesOff + i * 6
        guard idxOff >= 0, idxOff + 6 <= d.count else { return -1 }
        let off = stringsOff + Int(d.u32(idxOff))
        let len = Int(d.u16(idxOff + 4))
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
        let idxOff = codesOff + i * 6
        guard idxOff >= 0, idxOff + 6 <= d.count else { return false }
        let off = stringsOff + Int(d.u32(idxOff))
        let len = Int(d.u16(idxOff + 4))
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
        // 檔案大小限制
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let fileSize = attrs?[.size] as? UInt64 ?? 0
        guard fileSize <= 100_000_000 else {
            DebugLog.log("CIN file too large: \(fileSize) bytes, skipped")
            return
        }
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return }
        var inChardef = false
        var lineCount = 0
        let maxLines = 500_000
        content.enumerateLines { line, stop in
            lineCount += 1
            if lineCount > maxLines { stop = true; return }
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("%selkey ") {
                let keys = String(t.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                if !keys.isEmpty { self._selKeys = Array(keys) }; return
            }
            if t.hasPrefix("%cname ") {
                self._cinName = String(t.dropFirst(7)).trimmingCharacters(in: .whitespaces); return
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
        var dirs = [dir]
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
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("#") { return }
                let parts = t.split(separator: "\t", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return }
                let code = parts[0].lowercased()
                self.overlay[code, default: []].append(parts[1])
            }
        }
    }

    private func loadCharMaps() {
        let sharedDir = AppConstants.sharedDir + "/"
        let bundlePath = (Bundle.main.resourcePath ?? "") + "/"
        // 寫入 private 儲存區（呼叫端已持鎖）
        for (name, kp) in [("t2s", \CINTable._t2s), ("s2t", \CINTable._s2t)] {
            let shared = sharedDir + name + ".json"
            let bundled = bundlePath + name + ".json"
            let p = FileManager.default.fileExists(atPath: shared) ? shared : bundled
            guard let data = FileManager.default.contents(atPath: p) else { continue }
            do { self[keyPath: kp] = try JSONDecoder().decode([String: String].self, from: data) }
            catch { DebugLog.log("CINTable loadCharMaps \(name): \(error.localizedDescription)") }
        }
    }

    // MARK: - Lookup (public API) — 每個公開方法鎖一次，內部 helper 假設已持鎖

    func lookup(_ code: String) -> [String] {
        locked { lookupLocked(code) }
    }

    /// lookup 本體（須持鎖）
    private func lookupLocked(_ code: String) -> [String] {
        let c = code.lowercased()
        var result: [String] = []
        let idx = binSearch(c)
        if idx >= 0, let d = binData { result = readChars(d, at: idx) }
        if let extra = overlay[c] { result = extra + result }
        return result
    }

    func hasPrefix(_ prefix: String) -> Bool {
        locked {
            let p = prefix.lowercased()
            // Binary: check via binary search
            if let d = binData {
                let i = lowerBound(p)
                if i < entryCount && codeHasPrefix(d, at: i, p.utf8) { return true }
            }
            // Overlay: scan keys
            return overlay.keys.contains { $0.hasPrefix(p) }
        }
    }

    func validNextKeys(after prefix: String) -> Set<Character> {
        locked {
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
    }

    func wildcardLookup(_ pattern: String) -> [String] {
        locked {
            let pat = pattern.lowercased()
            guard pat.contains("*") else { return lookupLocked(pat) }
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
    }

    func reverseLookup(_ char: String) -> [String] { locked { reverseTableLocked[char] ?? [] } }
    func convert(_ char: String, map: [String: String]) -> String { map[char] ?? char }
}
