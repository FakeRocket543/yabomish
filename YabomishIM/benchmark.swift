import Foundation

// Inline CINTable for benchmark
final class CINTable {
    private var table: [String: [String]] = [:]
    private var prefixes: Set<String> = []
    var count: Int { table.count }

    func load(path: String) {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return }
        var inChardef = false
        table.reserveCapacity(100_000)
        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "%chardef begin" { inChardef = true; return }
            if trimmed == "%chardef end" { inChardef = false; return }
            guard inChardef else { return }
            let parts: [String]
            if trimmed.contains("\t") {
                parts = trimmed.split(separator: "\t", maxSplits: 1).map(String.init)
            } else {
                parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            }
            guard parts.count == 2 else { return }
            let code = parts[0].lowercased()
            self.table[code, default: []].append(parts[1])
            for i in 1...code.count { self.prefixes.insert(String(code.prefix(i))) }
        }
    }
    func lookup(_ code: String) -> [String] { table[code.lowercased()] ?? [] }
    func hasPrefix(_ prefix: String) -> Bool { prefixes.contains(prefix.lowercased()) }
}

let cinPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let t = CINTable()

// 1. Load benchmark
let loadStart = CFAbsoluteTimeGetCurrent()
t.load(path: cinPath)
let loadTime = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
print("=== CIN 表載入 ===")
print("碼數: \(t.count)")
print("載入時間: \(String(format: "%.2f", loadTime)) ms")

// 2. Lookup benchmark - 1,000,000 lookups
let testCodes = ["a", "aa", "aaa", "e", "gg", "ooo", "xyz", "bcd", "liu", "zz"]
let lookupCount = 1_000_000
let lookupStart = CFAbsoluteTimeGetCurrent()
for i in 0..<lookupCount {
    _ = t.lookup(testCodes[i % testCodes.count])
}
let lookupTime = (CFAbsoluteTimeGetCurrent() - lookupStart) * 1000
let perLookup = lookupTime / Double(lookupCount) * 1_000_000 // nanoseconds
print("\n=== 查碼速度 ===")
print("\(lookupCount) 次查詢: \(String(format: "%.2f", lookupTime)) ms")
print("每次查詢: \(String(format: "%.0f", perLookup)) ns")

// 3. Prefix check benchmark
let prefixCount = 1_000_000
let prefixStart = CFAbsoluteTimeGetCurrent()
for i in 0..<prefixCount {
    _ = t.hasPrefix(testCodes[i % testCodes.count])
}
let prefixTime = (CFAbsoluteTimeGetCurrent() - prefixStart) * 1000
let perPrefix = prefixTime / Double(prefixCount) * 1_000_000
print("\n=== 前綴驗證速度 ===")
print("\(prefixCount) 次查詢: \(String(format: "%.2f", prefixTime)) ms")
print("每次查詢: \(String(format: "%.0f", perPrefix)) ns")

// 4. Memory estimate
let memInfo = ProcessInfo.processInfo.physicalMemory
let rusage_self: Int32 = 0
var usage = rusage()
getrusage(rusage_self, &usage)
print("\n=== 記憶體 ===")
print("RSS: \(usage.ru_maxrss / 1024 / 1024) MB")
