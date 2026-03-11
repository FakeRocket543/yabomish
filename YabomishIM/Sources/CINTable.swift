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
    private var prefixes: Set<String> = []
    private(set) var selKeys: [Character] = Array("1234567890")
    private(set) var cinName: String = ""

    var isEmpty: Bool { table.isEmpty }

    // MARK: - Load

    func load(path: String) {
        let cachePath = path + ".cache"
        if loadCache(cachePath), !isCacheStale(cinPath: path, cachePath: cachePath) {
            NSLog("YabomishIM: Loaded cache (%d codes) in instant", table.count)
            return
        }
        parseCIN(path: path)
        saveCache(cachePath)
        NSLog("YabomishIM: Parsed %d codes from %@, cache saved", table.count, path)
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
        for (code, chars) in table {
            guard fixedPrefix.isEmpty || code.hasPrefix(fixedPrefix) else { continue }
            let range = NSRange(code.startIndex..., in: code)
            if re.firstMatch(in: code, range: range) != nil {
                results.append(contentsOf: chars)
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
}
