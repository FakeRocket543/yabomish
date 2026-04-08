import Foundation
import NaturalLanguage

/// Suggestion engine: generates word/char/emoji suggestions after commit.
final class SuggestionEngine {
    static let shared = SuggestionEngine()

    private let skipWords: Set<String> = ["的","了","在","是","和","與","或","而","但","也","都","就","被","把","讓","給","從","到","對","為"]

    /// Generate suggestions based on recently committed text.
    func suggest(recentCommitted: String, lastText: String) -> [String] {
        guard !recentCommitted.isEmpty else { return [] }

        let wantWord = YabomishPrefs.wordSuggest
        let wantChar = YabomishPrefs.charSuggest
        guard wantWord || wantChar else { return [] }

        // NLTokenizer 虛詞過濾
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = recentCommitted
        tokenizer.setLanguage(.traditionalChinese)
        var lastToken = ""
        tokenizer.enumerateTokens(in: recentCommitted.startIndex..<recentCommitted.endIndex) { range, _ in
            lastToken = String(recentCommitted[range]); return true
        }
        guard !skipWords.contains(lastToken) else { return [] }

        var suggestions: [String] = []
        var seen = Set<String>()

        if wantWord {
            suggestWords(recentCommitted: recentCommitted, suggestions: &suggestions, seen: &seen)
        }
        if wantChar {
            suggestChars(recentCommitted: recentCommitted, lastText: lastText, suggestions: &suggestions, seen: &seen)
        }
        if wantWord {
            suggestEmoji(recentCommitted: recentCommitted, suggestions: &suggestions, seen: &seen)
        }

        return Array(suggestions.prefix(10))
    }

    // MARK: - Word-level

    private func suggestWords(recentCommitted: String, suggestions: inout [String], seen: inout Set<String>) {
        // Layer 1: 萌典詞組補全
        if recentCommitted.count >= 2 {
            for len in stride(from: min(4, recentCommitted.count), through: 2, by: -1) {
                let prefix = String(recentCommitted.suffix(len))
                for r in WikiCorpus.shared.phraseCompletions(for: prefix) {
                    if seen.insert(r).inserted { suggestions.append(r) }
                }
                if suggestions.count >= 3 { break }
            }
        }

        // Layer 2: ngram + 成語 (order by pref)
        if recentCommitted.count >= 2 {
            let tok = NLTokenizer(unit: .word)
            tok.string = recentCommitted
            tok.setLanguage(.traditionalChinese)
            var words: [String] = []
            tok.enumerateTokens(in: recentCommitted.startIndex..<recentCommitted.endIndex) { range, _ in
                words.append(String(recentCommitted[range])); return true
            }
            let ctx = words.suffix(2).filter { $0.count >= 2 }

            if YabomishPrefs.chengyuFirst {
                appendChengyu(recentCommitted: recentCommitted, suggestions: &suggestions, seen: &seen)
                appendNgram(ctx: ctx, suggestions: &suggestions, seen: &seen)
            } else {
                appendNgram(ctx: ctx, suggestions: &suggestions, seen: &seen)
                appendChengyu(recentCommitted: recentCommitted, suggestions: &suggestions, seen: &seen)
            }
        }

        // Layer 3: 領域詞庫（只查最長 prefix，找到就停）
        if recentCommitted.count >= 2 {
            let prefix = String(recentCommitted.suffix(min(4, recentCommitted.count)))
            for s in WikiCorpus.shared.suggestDomainTerms(prefix: prefix) {
                if seen.insert(s).inserted { suggestions.append(s) }
            }
        }
    }

    // MARK: - Char-level

    private func appendNgram(ctx: [String], suggestions: inout [String], seen: inout Set<String>) {
        guard !ctx.isEmpty else { return }
        for w in WikiCorpus.shared.suggestWordNgram(context: ctx) {
            if seen.insert(w).inserted { suggestions.append(w) }
        }
    }

    private func appendChengyu(recentCommitted: String, suggestions: inout [String], seen: inout Set<String>) {
        for len in stride(from: min(6, recentCommitted.count), through: 2, by: -1) {
            let prefix = String(recentCommitted.suffix(len))
            for s in WikiCorpus.shared.suggestChengyu(prefix: prefix) {
                if seen.insert(s).inserted { suggestions.append(s) }
            }
            if suggestions.count >= 5 { break }
        }
    }

    private func suggestChars(recentCommitted: String, lastText: String, suggestions: inout [String], seen: inout Set<String>) {
        // Trigram
        if recentCommitted.count >= 2 {
            let prev2 = String(recentCommitted.suffix(2).prefix(1))
            let prev1 = String(recentCommitted.suffix(1))
            for ch in WikiCorpus.shared.suggestTrigram(prev2: prev2, prev1: prev1) {
                if seen.insert(ch).inserted { suggestions.append(ch) }
            }
        }
        // Bigram
        for ch in BigramSuggest.shared.suggest(after: lastText) {
            if seen.insert(ch).inserted { suggestions.append(ch) }
        }
    }

    // MARK: - Emoji

    private func suggestEmoji(recentCommitted: String, suggestions: inout [String], seen: inout Set<String>) {
        let lastChar = String(recentCommitted.suffix(1))
        for e in WikiCorpus.shared.suggestEmoji(for: lastChar) {
            if seen.insert(e).inserted { suggestions.append(e) }
        }
    }
}
