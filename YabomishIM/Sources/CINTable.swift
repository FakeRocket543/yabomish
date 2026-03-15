import Foundation

/// v3: Trie-based lookup engine with binary cache, wildcard DFS, selkey from .cin header
final class CINTable {

    // MARK: - Trie

    private final class Node {
        var children: [Character: Node] = [:]
        var values: [String]?           // non-nil = valid code terminus
    }

    private var root = Node()
    private var entryCount = 0

    private var _reverseTable: [String: [String]]?
    private var reverseTable: [String: [String]] {
        if let cached = _reverseTable { return cached }
        var rev: [String: [String]] = [:]
        enumerateTrie { code, chars in
            for c in chars { rev[c, default: []].append(code) }
        }
        _reverseTable = rev
        return rev
    }

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

    private(set) var t2s: [String: String] = [:]
    private(set) var s2t: [String: String] = [:]
    private(set) var selKeys: [Character] = Array("1234567890")
    private(set) var cinName: String = ""

    var isEmpty: Bool { entryCount == 0 }

    func reload() {
        root = Node(); entryCount = 0
        _reverseTable = nil; _shortestCodes = nil; _longestCodes = nil
        t2s = [:]; s2t = [:]
        let userPath = NSHomeDirectory() + "/Library/YabomishIM/liu.cin"
        let bundlePath = Bundle.main.path(forResource: "liu", ofType: "cin")
        if FileManager.default.fileExists(atPath: userPath) { load(path: userPath) }
        else if let p = bundlePath { load(path: p) }
    }

    // MARK: - Trie helpers

    private func insert(code: String, value: String) {
        var node = root
        for ch in code {
            if node.children[ch] == nil { node.children[ch] = Node() }
            node = node.children[ch]!
        }
        if node.values == nil { node.values = [value]; entryCount += 1 }
        else { node.values!.append(value) }
    }

    private func find(_ code: String) -> Node? {
        var node = root
        for ch in code {
            guard let next = node.children[ch] else { return nil }
            node = next
        }
        return node
    }

    /// Walk entire trie, calling visitor for each code that has values.
    private func enumerateTrie(_ visitor: (String, [String]) -> Void) {
        var stack: [(Node, String)] = [(root, "")]
        while !stack.isEmpty {
            let (node, prefix) = stack.removeLast()
            if let vals = node.values { visitor(prefix, vals) }
            for (ch, child) in node.children { stack.append((child, prefix + String(ch))) }
        }
    }

    // MARK: - Load

    func load(path: String) {
        let cachePath = path + ".cache"
        if loadCache(cachePath), !isCacheStale(cinPath: path, cachePath: cachePath) {
            NSLog("YabomishIM: Loaded cache (%d codes) in instant", entryCount)
        } else {
            parseCIN(path: path)
            saveCache(cachePath)
            NSLog("YabomishIM: Parsed %d codes from %@, cache saved", entryCount, path)
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
        root = Node(); entryCount = 0
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
            self.insert(code: code, value: value)
        }
        _reverseTable = nil
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
        let header = "\(String(selKeys))\t\(cinName)\n"
        data.append(header.data(using: .utf8)!)
        enumerateTrie { code, chars in
            let line = code + "\t" + chars.joined(separator: "\t") + "\n"
            data.append(line.data(using: .utf8)!)
        }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private func loadCache(_ path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return false }
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return false }

        let headerParts = lines.removeFirst().split(separator: "\t", maxSplits: 1).map(String.init)
        if headerParts.count >= 1 { selKeys = Array(headerParts[0]) }
        if headerParts.count >= 2 { cinName = headerParts[1] }

        root = Node(); entryCount = 0
        for line in lines where !line.isEmpty {
            let parts = line.split(separator: "\t").map(String.init)
            guard parts.count >= 2 else { continue }
            let code = parts[0]
            for v in parts[1...] { insert(code: code, value: v) }
        }
        _reverseTable = nil
        return entryCount > 0
    }

    // MARK: - Lookup

    /// Exact match
    func lookup(_ code: String) -> [String] {
        find(code.lowercased())?.values ?? []
    }

    /// Wildcard lookup: `*` matches one or more characters via Trie DFS
    func wildcardLookup(_ pattern: String) -> [String] {
        let pat = Array(pattern.lowercased())
        guard pat.contains("*") else { return lookup(String(pat)) }
        var results: [String] = []
        var seen = Set<String>()

        func dfs(_ node: Node, _ pi: Int) {
            if pi == pat.count {
                if let vals = node.values {
                    for v in vals where seen.insert(v).inserted { results.append(v) }
                }
                return
            }
            if pat[pi] == "*" {
                // * matches 1+ characters: descend into every child, then continue matching rest or keep expanding
                for (_, child) in node.children {
                    dfs(child, pi + 1)   // * matched exactly 1 char
                    dfs(child, pi)       // * matched 1 char, keep matching more
                }
            } else {
                if let child = node.children[pat[pi]] {
                    dfs(child, pi + 1)
                }
            }
        }

        dfs(root, 0)
        return results
    }

    /// Check if any code starts with this prefix
    func hasPrefix(_ prefix: String) -> Bool {
        find(prefix.lowercased()) != nil
    }

    func reverseLookup(_ char: String) -> [String] {
        reverseTable[char] ?? []
    }

    /// Convert a character using t2s or s2t map
    func convert(_ char: String, map: [String: String]) -> String {
        map[char] ?? char
    }
}
