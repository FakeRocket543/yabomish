import Foundation

/// Candidate ranking: freq-based sorting, mode filtering, domain context, fuzzy match.
final class CandidateRanker {

    // MARK: - Domain context tracking (MoE-style)

    /// Session domain hit counts: domain_key → cumulative weight
    private var domainHits: [String: Int] = [:]
    private var domainCache: [String: Set<String>] = [:]  // char → domain keys it belongs to

    /// Called after each commit to update domain context
    func updateDomainContext(_ text: String) {
        guard YabomishPrefs.suggestStrategy == "domain" else { return }
        for ch in text {
            let s = String(ch)
            let domains = domainsFor(s)
            for d in domains { domainHits[d, default: 0] += 1 }
        }
    }

    /// Domain boost score for a candidate (0.0 ~ 1.0)
    func domainBoost(for char: String) -> Double {
        guard !domainHits.isEmpty else { return 0 }
        let domains = domainsFor(char)
        guard !domains.isEmpty else { return 0 }
        let total = domainHits.values.reduce(0, +)
        guard total > 0 else { return 0 }
        var score = 0
        for d in domains { score += domainHits[d] ?? 0 }
        return Double(score) / Double(total)
    }

    func resetDomainContext() { domainHits.removeAll() }

    /// Check which enabled domains contain this character
    private func domainsFor(_ char: String) -> Set<String> {
        if let cached = domainCache[char] { return cached }
        var result = Set<String>()
        for (key, _, _) in WikiCorpus.domainKeys {
            guard YabomishPrefs.domainEnabled(key) else { continue }
            // Check if domain has completions starting with this char
            let hits = WikiCorpus.shared.suggestDomainTerms(prefix: char, limit: 1)
            if !hits.isEmpty { result.insert(key) }
        }
        domainCache[char] = result
        return result
    }

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

        // Domain-aware reranking (stable sort — only reorder when boost differs)
        if YabomishPrefs.suggestStrategy == "domain" && !domainHits.isEmpty && candidates.count > 1 {
            candidates.sort { domainBoost(for: $0) > domainBoost(for: $1) }
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
