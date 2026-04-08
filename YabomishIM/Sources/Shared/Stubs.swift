import Foundation

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
