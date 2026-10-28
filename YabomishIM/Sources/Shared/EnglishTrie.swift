import Foundation

/// Prefix trie for English word completion（移植自 yabomish iOS 版）。
/// Loads google-10000-english (Public Domain) — ~80KB, <1ms lookup.
final class EnglishTrie {

    /// var：e2e 測試可注入小型詞表（`EnglishTrie.shared = EnglishTrie(words: [...])`）。
    static var shared = EnglishTrie()

    private final class Node {
        var children: [UInt8: Node] = [:]
        var word: String?
        var rank: Int = 0
    }

    private let root = Node()
    private(set) var wordCount = 0

    private init() {
        guard let path = Bundle.main.path(forResource: "english_10k", ofType: "txt"),
              let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        for (rank, line) in text.components(separatedBy: "\n").enumerated() {
            let w = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !w.isEmpty else { continue }
            insert(w, rank: rank)
        }
    }

    /// 測試／嵌入用：直接餵詞表（陣列序即字頻 rank，越前面越高頻）。
    init(words: [String]) {
        for (rank, w) in words.enumerated() {
            let word = w.lowercased()
            guard !word.isEmpty else { continue }
            insert(word, rank: rank)
        }
    }

    private func insert(_ word: String, rank: Int) {
        var node = root
        for byte in word.utf8 {
            if node.children[byte] == nil { node.children[byte] = Node() }
            node = node.children[byte]!
        }
        node.word = word
        node.rank = rank
        wordCount += 1
    }

    /// Find up to `limit` words matching the given prefix, sorted by frequency rank.
    func search(prefix: String, limit: Int = 8) -> [String] {
        let p = prefix.lowercased()
        var node = root
        for byte in p.utf8 {
            guard let next = node.children[byte] else { return [] }
            node = next
        }
        var results: [(String, Int)] = []
        var stack: [Node] = [node]
        while !stack.isEmpty && results.count < limit * 2 {
            let n = stack.removeLast()
            if let w = n.word { results.append((w, n.rank)) }
            for (_, child) in n.children { stack.append(child) }
        }
        results.sort { $0.1 < $1.1 }
        return Array(results.prefix(limit).map(\.0))
    }
}
