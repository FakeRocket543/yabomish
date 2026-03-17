import Foundation

/// v2: Binary cache for instant load, wildcard support, selkey from .cin header
final class CINTable {
    private var table: [String: [String]] = [:]
    private var _reverseTable: [String: [String]]?
    private var reverseTable: [String: [String]] {
        if let cached = _reverseTable { return cached }
        var newReverse: [String: [String]] = [:]
        for (code, chars) in table {
            for char in chars {
                newReverse[char, default: []].append(code)
            }
        }
        _reverseTable = newReverse
        return newReverse
    }

    // Shortest code(s) per character (for ,,SP mode) — may have multiple equal-length codes
    private var _shortestCodes: [String: Set<String>]?
    var shortestCodesTable: [String: Set<String>] {
        if let cached = _shortestCodes { return cached }
        var result: [String: Set<String>] = [:]
        for (char, codes) in reverseTable {
            let minLen = codes.min(by: { $0.count < $1.count })?.count ?? 0
            result[char] = Set(codes.filter { $0.count == minLen })
        }
        _shortestCodes = result
        return result
    }

    // Longest code(s) per character (for ,,SL mode)
    private var _longestCodes: [String: Set<String>]?
    var longestCodesTable: [String: Set<String>] {
        if let cached = _longestCodes { return cached }
        var result: [String: Set<String>] = [:]
        for (char, codes) in reverseTable {
            let maxLen = codes.max(by: { $0.count < $1.count })?.count ?? 0
            result[char] = Set(codes.filter { $0.count == maxLen })
        }
        _longestCodes = result
        return result
    }

    // Traditional ↔ Simplified character maps
    private(set) var t2s: [String: String] = [:]  // 繁中→簡中
    private(set) var s2t: [String: String] = [:]  // 簡中→繁中
    private var prefixes: Set<String> = []
    private(set) var selKeys: [Character] = Array("1234567890")
    private(set) var cinName: String = ""

    var isEmpty: Bool { table.isEmpty }
    private(set) var maxCodeLength: Int = 4

    func reload() {
        table = [:]
        _reverseTable = nil
        _shortestCodes = nil
        _longestCodes = nil
        t2s = [:]
        s2t = [:]
        prefixes = []
        let userPath = NSHomeDirectory() + "/Library/YabomishIM/liu.cin"
        let bundlePath = Bundle.main.path(forResource: "liu", ofType: "cin")
        if FileManager.default.fileExists(atPath: userPath) { load(path: userPath) }
        else if let p = bundlePath { load(path: p) }
        loadExtras()
        maxCodeLength = table.keys.map(\.count).max() ?? 4
        NSLog("YabomishIM: maxCodeLength = %d", maxCodeLength)
    }

    /// Load tab-separated extras from ~/Library/YabomishIM/tables/*.txt (+ sync folder)
    private func loadExtras() {
        var dirs = [NSHomeDirectory() + "/Library/YabomishIM/tables"]
        if let sync = YabomishPrefs.syncFolder {
            dirs.append((sync as NSString).appendingPathComponent("tables"))
        }
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for file in files where file.hasSuffix(".txt") {
                let path = dir + "/" + file
                guard let data = FileManager.default.contents(atPath: path),
                      let content = String(data: data, encoding: .utf8) else { continue }
                var count = 0
                content.enumerateLines { line, _ in
                    let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else { return }
                    let code = parts[0].lowercased()
                    let value = parts[1]
                    self.table[code, default: []].append(value)
                    for i in 1...code.count { self.prefixes.insert(String(code.prefix(i))) }
                    count += 1
                }
                NSLog("YabomishIM: Loaded %d entries from %@/%@", count, dir, file)
            }
        }
    }

    // MARK: - Load

    func load(path: String) {
        let cachePath = path + ".cache"
        if loadCache(cachePath), !isCacheStale(cinPath: path, cachePath: cachePath) {
            NSLog("YabomishIM: Loaded cache (%d codes) in instant", table.count)
        } else {
            parseCIN(path: path)
            saveCache(cachePath)
            NSLog("YabomishIM: Parsed %d codes from %@, cache saved", table.count, path)
        }
        loadCharMaps()
    }

    private func loadCharMaps() {
        let userDir = NSHomeDirectory() + "/Library/YabomishIM/"
        let bundlePath = Bundle.main.resourcePath ?? ""
        for (name, target) in [("t2s", \CINTable.t2s), ("s2t", \CINTable.s2t)] {
            let userFile = userDir + name + ".json"
            let bundleFile = bundlePath + "/" + name + ".json"
            let path = FileManager.default.fileExists(atPath: userFile) ? userFile : bundleFile
            guard let data = FileManager.default.contents(atPath: path),
                  let map = try? JSONDecoder().decode([String: String].self, from: data) else {
                NSLog("YabomishIM: Failed to load %@.json", name)
                continue
            }
            self[keyPath: target] = map
            NSLog("YabomishIM: Loaded %@.json (%d entries)", name, map.count)
        }
    }

    // MARK: - CIN Parser

    private func parseCIN(path: String) {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            NSLog("YabomishIM: Failed to read %@", path)
            return
        }
        var newTable: [String: [String]] = [:]
        newTable.reserveCapacity(100_000)
        var newPrefixes: Set<String> = []
        var inChardef = false

        content.enumerateLines { line, _ in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("%selkey ") {
                let keys = String(t.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                if !keys.isEmpty { self.selKeys = Array(keys) }
                return
            }
            if t.hasPrefix("%cname ") {
                self.cinName = String(t.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                return
            }
            if t == "%chardef begin" { inChardef = true; return }
            if t == "%chardef end" { inChardef = false; return }
            guard inChardef else { return }

            let parts: [String]
            if t.contains("\t") {
                parts = t.split(separator: "\t", maxSplits: 1).map(String.init)
            } else {
                parts = t.split(separator: " ", maxSplits: 1).map(String.init)
            }
            guard parts.count == 2 else { return }
            let code = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            newTable[code, default: []].append(value)
            for i in 1...code.count { newPrefixes.insert(String(code.prefix(i))) }
        }
        self.table = newTable
        self.prefixes = newPrefixes
        self._reverseTable = nil
    }

    // MARK: - Binary Cache

    private func isCacheStale(cinPath: String, cachePath: String) -> Bool {
        guard let cinAttr = try? FileManager.default.attributesOfItem(atPath: cinPath),
              let cacheAttr = try? FileManager.default.attributesOfItem(atPath: cachePath),
              let cinDate = cinAttr[.modificationDate] as? Date,
              let cacheDate = cacheAttr[.modificationDate] as? Date else { return true }
        return cinDate > cacheDate
    }

    private func saveCache(_ path: String) {
        var data = Data()
        // Header: selKeys + cinName
        let header = "\(String(selKeys))\t\(cinName)\n"
        data.append(header.data(using: .utf8)!)
        // Entries: code\tchar1\tchar2...\n
        for (code, chars) in table {
            let line = code + "\t" + chars.joined(separator: "\t") + "\n"
            data.append(line.data(using: .utf8)!)
        }
        // Prefixes not cached — rebuilt from table on load
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private func loadCache(_ path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return false }
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return false }

        // Header
        let headerParts = lines.removeFirst().split(separator: "\t", maxSplits: 1).map(String.init)
        if headerParts.count >= 1 { selKeys = Array(headerParts[0]) }
        if headerParts.count >= 2 { cinName = headerParts[1] }

        var newTable: [String: [String]] = [:]
        newTable.reserveCapacity(lines.count)
        var newPrefixes: Set<String> = []

        for line in lines where !line.isEmpty {
            let parts = line.split(separator: "\t").map(String.init)
            guard parts.count >= 2 else { continue }
            let code = parts[0]
            newTable[code] = Array(parts[1...])
            for i in 1...code.count { newPrefixes.insert(String(code.prefix(i))) }
        }
        self.table = newTable
        self.prefixes = newPrefixes
        self._reverseTable = nil
        return !newTable.isEmpty
    }

    // MARK: - Lookup

    /// Exact match
    func lookup(_ code: String) -> [String] {
        table[code.lowercased()] ?? []
    }

    /// Wildcard lookup: `*` matches one or more characters
    func wildcardLookup(_ pattern: String) -> [String] {
        let pat = pattern.lowercased()
        guard pat.contains("*") else { return lookup(pat) }

        let regex = "^" + NSRegularExpression.escapedPattern(for: pat)
            .replacingOccurrences(of: "\\*", with: ".+") + "$"
        guard let re = try? NSRegularExpression(pattern: regex) else { return [] }

        let fixedPrefix = String(pat.prefix(while: { $0 != "*" }))
        var results: [String] = []
        var seen = Set<String>()
        for (code, chars) in table {
            guard fixedPrefix.isEmpty || code.hasPrefix(fixedPrefix) else { continue }
            let range = NSRange(code.startIndex..., in: code)
            if re.firstMatch(in: code, range: range) != nil {
                for c in chars where seen.insert(c).inserted { results.append(c) }
            }
        }
        return results
    }

    /// Check if any code starts with this prefix
    func hasPrefix(_ prefix: String) -> Bool {
        prefixes.contains(prefix.lowercased())
    }
    
    func reverseLookup(_ char: String) -> [String] {
        reverseTable[char] ?? []
    }

    /// Convert a character using t2s or s2t map
    func convert(_ char: String, map: [String: String]) -> String {
        map[char] ?? char
    }
}
