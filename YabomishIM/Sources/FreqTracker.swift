import Foundation

final class FreqTracker {
    private var freq: [String: [String: Int]] = [:]
    private var bigram: [String: [String: Int]] = [:]
    private let path: String
    private var dirty = false
    private var recordCount = 0
    private var saveTimer: Timer?

    private struct Storage: Codable {
        let freq: [String: [String: Int]]
        let bigram: [String: [String: Int]]
    }

    init() {
        let dir = NSHomeDirectory() + "/Library/YabomishIM"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        self.path = dir + "/freq.json"
        load()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.saveIfNeeded()
        }
    }

    func record(code: String, char: String) {
        freq[code, default: [:]][char, default: 0] += 1
        dirty = true
        recordCount += 1
        if recordCount >= 500 {
            recordCount = 0
            decay()
        }
    }

    func recordBigram(prev: String, char: String) {
        bigram[prev, default: [:]][char, default: 0] += 1
        dirty = true
    }

    func sorted(_ candidates: [String], forCode code: String) -> [String] {
        guard let counts = freq[code] else { return candidates }
        return candidates.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
    }

    func sortedWithContext(_ candidates: [String], forCode code: String, prev: String) -> [String] {
        guard !prev.isEmpty else { return sorted(candidates, forCode: code) }
        let unigramCounts = freq[code] ?? [:]
        let bigramCounts = bigram[prev] ?? [:]
        return candidates.sorted {
            let score0 = Double(unigramCounts[$0] ?? 0) * 0.7 + Double(bigramCounts[$0] ?? 0) * 0.3
            let score1 = Double(unigramCounts[$1] ?? 0) * 0.7 + Double(bigramCounts[$1] ?? 0) * 0.3
            return score0 > score1
        }
    }

    func decay(factor: Double = 0.9) {
        for (code, counts) in freq {
            var updated: [String: Int] = [:]
            for (char, count) in counts {
                let newCount = Int(Double(count) * factor)
                if newCount >= 1 { updated[char] = newCount }
            }
            freq[code] = updated.isEmpty ? nil : updated
        }
        for (prev, counts) in bigram {
            var updated: [String: Int] = [:]
            for (char, count) in counts {
                let newCount = Int(Double(count) * factor)
                if newCount >= 1 { updated[char] = newCount }
            }
            bigram[prev] = updated.isEmpty ? nil : updated
        }
        dirty = true
    }

    func saveIfNeeded() {
        guard dirty else { return }
        dirty = false
        let storage = Storage(freq: freq, bigram: bigram)
        guard let data = try? JSONEncoder().encode(storage) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
        if let storage = try? JSONDecoder().decode(Storage.self, from: data) {
            freq = storage.freq
            bigram = storage.bigram
        } else if let legacyFreq = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            freq = legacyFreq
        }
    }
}
