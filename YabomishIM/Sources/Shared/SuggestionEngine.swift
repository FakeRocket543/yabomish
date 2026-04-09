import Foundation

/// Suggestion engine: generates suggestions after commit.
final class SuggestionEngine {
    static let shared = SuggestionEngine()

    private let skipChars: Set<String> = ["的","了","在","是","和","與","或","而","但","也","都","就","被","把","讓","給","從","到","對","為","著","過","嗎","呢","吧","啊","喔","哦","啦"]

    func suggest(recentCommitted: String, lastText: String) -> [String] {
        guard !recentCommitted.isEmpty else { return [] }
        guard !skipChars.contains(String(recentCommitted.suffix(1))) else { return [] }

        var suggestions: [String] = []
        var seen = Set<String>()

        if recentCommitted.count >= 2 {
            let prefix = String(recentCommitted.suffix(min(4, recentCommitted.count)))

            // 第二層：詞級語料
            let pool2 = WikiCorpus.shared.suggestWordCorpus(prefix: prefix)
                .map { s in s.hasPrefix(prefix) ? String(s.dropFirst(prefix.count)) : s }
                .filter { !$0.isEmpty }

            // 第三層：詞庫
            let pool3 = WikiCorpus.shared.suggestAllDomains(prefix: prefix)
                .map { s in s.hasPrefix(prefix) ? String(s.dropFirst(prefix.count)) : s }
                .filter { !$0.isEmpty }

            let ordered = YabomishPrefs.suggestStrategy == "domain" ? pool3 + pool2 : pool2 + pool3
            for s in ordered where seen.insert(s).inserted { suggestions.append(s) }
        }

        // 第四層：字級
        if YabomishPrefs.charSuggest {
            if recentCommitted.count >= 2 {
                let prev2 = String(recentCommitted.suffix(2).prefix(1))
                let prev1 = String(recentCommitted.suffix(1))
                for ch in WikiCorpus.shared.suggestTrigram(prev2: prev2, prev1: prev1) {
                    if seen.insert(ch).inserted { suggestions.append(ch) }
                }
            }
            for ch in BigramSuggest.shared.suggest(after: lastText) {
                if seen.insert(ch).inserted { suggestions.append(ch) }
            }
        }

        // Emoji
        let lastChar = String(recentCommitted.suffix(1))
        for e in WikiCorpus.shared.suggestEmoji(for: lastChar) {
            if seen.insert(e).inserted { suggestions.append(e) }
        }

        return Array(suggestions.prefix(10))
    }
}
