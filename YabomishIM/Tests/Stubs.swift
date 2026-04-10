import Foundation

// Stubs for types defined in excluded UI files

final class DomainOrderManager {
    static let shared = DomainOrderManager()
    func allOrderedKeys() -> [String] {
        let saved = UserDefaults.standard.stringArray(forKey: "domainOrder") ?? []
        let allKeys = WikiCorpus.domainKeys.map { $0.key }
        var ordered = saved.filter { allKeys.contains($0) }
        for k in allKeys where !ordered.contains(k) { ordered.append(k) }
        return ordered
    }
}
