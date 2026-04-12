import Foundation

/// Suggestion engine: generates suggestions after commit.
final class SuggestionEngine {
    static let shared = SuggestionEngine()

    private let wikiCorpus: WikiCorpus
    private let bigramSuggest: BigramSuggest
    private let prefs: IMEPreferences

    init(wikiCorpus: WikiCorpus = .shared, bigramSuggest: BigramSuggest = .shared,
         prefs: IMEPreferences = DefaultPreferences.shared) {
        self.wikiCorpus = wikiCorpus
        self.bigramSuggest = bigramSuggest
        self.prefs = prefs
    }

    private let skipChars: Set<String> = ["的","了","在","是","和","與","或","而","但","也","都","就","被","把","讓","給","從","到","對","為","著","過","嗎","呢","吧","啊","喔","哦","啦"]

    func suggest(recentCommitted: String, lastText: String) -> [String] {
        guard !recentCommitted.isEmpty else { return [] }
        let lastChar = String(recentCommitted.suffix(1))
        let isSkipChar = skipChars.contains(lastChar)

        let strategy = prefs.suggestStrategy
        let prefix = recentCommitted.count >= 2
            ? String(recentCommitted.suffix(min(4, recentCommitted.count))) : ""

        var suggestions: [String] = []
        var seen = Set<String>()

        let pool2 = (!isSkipChar && !prefix.isEmpty) ? wikiCorpus.suggestWordCorpus(prefix: prefix)
            .map { s in s.hasPrefix(prefix) ? String(s.dropFirst(prefix.count)) : s }
            .filter { !$0.isEmpty } : []

        var pool3: [String] = []
        if recentCommitted.count >= 2 {
            for len in stride(from: min(4, recentCommitted.count), through: 2, by: -1) {
                let p = String(recentCommitted.suffix(len))
                pool3 = wikiCorpus.suggestAllDomains(prefix: p)
                    .map { s in s.hasPrefix(p) ? String(s.dropFirst(p.count)) : s }
                    .filter { !$0.isEmpty }
                if !pool3.isEmpty { break }
            }
        }
        // Single-char domain fallback (e.g. jingjing-ti: "被" → "cue到", "很" → "chill")
        if pool3.isEmpty && recentCommitted.count >= 1 {
            let p = String(recentCommitted.suffix(1))
            pool3 = wikiCorpus.suggestDomainTerms(prefix: p, limit: 5)
        }

        // Jingjing-ti phrase expansion: independent pool, supports single-char prefix
        var poolJJ: [String] = []
        for len in stride(from: min(4, recentCommitted.count), through: 1, by: -1) {
            let p = String(recentCommitted.suffix(len))
            poolJJ = wikiCorpus.suggestJingjing(prefix: p, limit: 5)
            if !poolJJ.isEmpty { break }
        }

        var pool4: [String] = []
        if !isSkipChar && prefs.charSuggest {
            if recentCommitted.count >= 2 {
                let prev2 = String(recentCommitted.suffix(2).prefix(1))
                let prev1 = String(recentCommitted.suffix(1))
                pool4 += wikiCorpus.suggestTrigram(prev2: prev2, prev1: prev1)
            }
            pool4 += bigramSuggest.suggest(after: lastText)
        }

        let ordered: [[String]]
        switch strategy {
        case "domain": ordered = [poolJJ, pool3, pool2, pool4]
        case "char":   ordered = [pool4, poolJJ, pool2, pool3]
        default:       ordered = [pool2, poolJJ, pool3, pool4]
        }
        for pool in ordered {
            for s in pool where seen.insert(s).inserted { suggestions.append(s) }
        }

        // Emoji
        for e in wikiCorpus.suggestEmoji(for: String(recentCommitted.suffix(1))) {
            if seen.insert(e).inserted { suggestions.append(e) }
        }

        return Array(suggestions.prefix(10))
    }
}
