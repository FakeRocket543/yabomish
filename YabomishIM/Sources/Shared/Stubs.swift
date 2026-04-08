import Foundation

// MARK: - Stubs for T1 scaffold (will be replaced in T7)
// These provide the API surface that SuggestionEngine expects.

final class WikiCorpus {
    static let shared = WikiCorpus()
    func phraseCompletions(for prefix: String) -> [String] { [] }
    func suggestWordNgram(context: [String]) -> [String] { [] }
    func suggestChengyu(prefix: String) -> [String] { [] }
    func suggestTrigram(prev2: String, prev1: String) -> [String] { [] }
    func suggestDomainTerms(prefix: String) -> [String] { [] }
    func suggestEmoji(for char: String) -> [String] { [] }
}

final class BigramSuggest {
    static let shared = BigramSuggest()
    func suggest(after text: String) -> [String] { [] }
}

// MARK: - API gap stubs (macOS CINTable/FreqTracker missing methods)

extension CINTable {
    func validNextKeys(after code: String) -> Set<Character> {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        return Set(letters.compactMap { ch in
            hasPrefix(code + String(ch)) ? ch : nil
        })
    }
    func releaseOptionalCaches() { /* no-op on macOS */ }
}

extension FreqTracker {
    func deferredMerge() { /* no-op on macOS for now */ }
    func recordTrigram(prev2: String, prev1: String, char: String) { /* no-op stub */ }
}

extension ZhuyinLookup {
    func sortByFreq(_ chars: [String], prevChar: String, curZhuyin: String) -> [String] {
        sortByFreq(chars)
    }
}
