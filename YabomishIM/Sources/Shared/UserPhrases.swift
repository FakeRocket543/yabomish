import Foundation

/// User-defined phrases for suggestion. Stored as a simple text file, one phrase per line.
/// Lookup: given a prefix char, return phrases starting with it.
final class UserPhrases {
    static let shared = UserPhrases()
    private var table: [Character: [String]] = [:]

    private init() { reload() }

    func reload() {
        table = [:]
        let path = AppConstants.sharedDir + "/user_phrases.txt"
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return }
        for line in content.split(separator: "\n") {
            let phrase = line.trimmingCharacters(in: .whitespaces)
            guard phrase.count >= 2, let first = phrase.first else { continue }
            table[first, default: []].append(phrase)
        }
    }

    /// Return phrases starting with `char`, returning the remainder (excluding first char)
    func suggest(after char: String, limit: Int = 3) -> [String] {
        guard let ch = char.first, let phrases = table[ch] else { return [] }
        return phrases.prefix(limit).map { String($0.dropFirst()) }
    }

    /// Return full phrases starting with `prefix`
    func completions(for prefix: String, limit: Int = 3) -> [String] {
        guard let first = prefix.first, let phrases = table[first] else { return [] }
        return phrases.filter { $0.hasPrefix(prefix) && $0.count > prefix.count }.prefix(limit).map { String($0) }
    }
}
