import Foundation

/// Suggestion engine: generates suggestions after commit.
final class SuggestionEngine {
    static let shared = SuggestionEngine()

    private let skipChars: Set<String> = ["的","了","在","是","和","與","或","而","但","也","都","就","被","把","讓","給","從","到","對","為","著","過","嗎","呢","吧","啊","喔","哦","啦"]

    func suggest(recentCommitted: String, lastText: String) -> [String] {
        guard !recentCommitted.isEmpty else { return [] }
        guard !skipChars.contains(String(recentCommitted.suffix(1))) else { return [] }

        let strategy = YabomishPrefs.suggestStrategy
        let prefix = recentCommitted.count >= 2
            ? String(recentCommitted.suffix(min(4, recentCommitted.count))) : ""

        var suggestions: [String] = []
        var seen = Set<String>()

        let pool2 = prefix.isEmpty ? [] : WikiCorpus.shared.suggestWordCorpus(prefix: prefix)
            .map { s in s.hasPrefix(prefix) ? String(s.dropFirst(prefix.count)) : s }
            .filter { !$0.isEmpty }

        let pool3 = prefix.isEmpty ? [] : WikiCorpus.shared.suggestAllDomains(prefix: prefix)
            .map { s in s.hasPrefix(prefix) ? String(s.dropFirst(prefix.count)) : s }
            .filter { !$0.isEmpty }

        var pool4: [String] = []
        if YabomishPrefs.charSuggest {
            if recentCommitted.count >= 2 {
                let prev2 = String(recentCommitted.suffix(2).prefix(1))
                let prev1 = String(recentCommitted.suffix(1))
                pool4 += WikiCorpus.shared.suggestTrigram(prev2: prev2, prev1: prev1)
            }
            pool4 += BigramSuggest.shared.suggest(after: lastText)
        }

        let ordered: [[String]]
        switch strategy {
        case "domain": ordered = [pool3, pool2, pool4]
        case "char":   ordered = [pool4, pool2, pool3]
        default:       ordered = [pool2, pool3, pool4]
        }
        for pool in ordered {
            for s in pool where seen.insert(s).inserted { suggestions.append(s) }
        }

        // Emoji
        for e in WikiCorpus.shared.suggestEmoji(for: String(recentCommitted.suffix(1))) {
            if seen.insert(e).inserted { suggestions.append(e) }
        }

        return Array(suggestions.prefix(10))
    }
}
