import Foundation

/// Candidate ranking: freq-based sorting, mode filtering, fuzzy match.
final class CandidateRanker {

    // MARK: - Mode filtering + ranking

    /// Sort and filter candidates based on current input mode.
    func rank(raw: [String], code: String, prev: String,
              mode: InputEngine.InputMode, cinTable: CINTable, freqTracker: FreqTracker) -> [String] {
        var candidates = freqTracker.sortedWithContext(raw, forCode: code, prev: prev)

        switch mode {
        case .sp:
            let tbl = cinTable.shortestCodesTable
            candidates = candidates.filter { tbl[$0]?.contains(code) == true }
        case .sl:
            let tbl = cinTable.longestCodesTable
            candidates = candidates.filter { tbl[$0]?.contains(code) == true }
        case .ts:
            var seen = Set<String>()
            candidates = candidates.compactMap { ch in
                let s = cinTable.convert(ch, map: cinTable.t2s)
                return seen.insert(s).inserted ? s : nil
            }
        case .st:
            var seen = Set<String>()
            candidates = candidates.compactMap { ch in
                let t = cinTable.convert(ch, map: cinTable.s2t)
                return seen.insert(t).inserted ? t : nil
            }
        case .s:
            let t2s = cinTable.t2s
            candidates = candidates.filter { ch in
                guard let s = t2s[ch] else { return true }; return s == ch
            }
        case .t, .j: break
        }

        return candidates
    }

    // MARK: - Adjacent-key fuzzy matching

    private static let adjacentKeys: [Character: [Character]] = {
        let rows: [[Character]] = [
            ["q","w","e","r","t","y","u","i","o","p"],
            ["a","s","d","f","g","h","j","k","l"],
            ["z","x","c","v","b","n","m"]
        ]
        var map: [Character: [Character]] = [:]
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() {
                var adj: [Character] = []
                for dc in [-1, 1] {
                    let nc = c + dc
                    if nc >= 0 && nc < row.count { adj.append(row[nc]) }
                }
                for dr in [-1, 1] {
                    let nr = r + dr
                    guard nr >= 0 && nr < rows.count else { continue }
                    let offsets = dr == -1 ? [c - 1, c] : (r == 0 ? [c, c + 1] : [c - 1, c])
                    for nc in offsets where nc >= 0 && nc < rows[nr].count {
                        adj.append(rows[nr][nc])
                    }
                }
                map[ch] = adj
            }
        }
        return map
    }()

    func fuzzyLookup(_ code: String, cinTable: CINTable) -> [String] {
        var seen = Set<String>()
        var results: [String] = []
        let chars = Array(code)
        for i in 0..<chars.count {
            guard let neighbors = Self.adjacentKeys[chars[i]] else { continue }
            for neighbor in neighbors {
                var variant = chars
                variant[i] = neighbor
                for ch in cinTable.lookup(String(variant)) where seen.insert(ch).inserted {
                    results.append(ch)
                }
            }
        }
        return Array(results.prefix(20))
    }
}
