import Foundation

final class DomainOrderManager {
    static let shared = DomainOrderManager()
    private let defaults = UserDefaults.standard
    private let orderKey = "domainOrder"

    func orderedKeys(for group: [(key: String, file: String, label: String)]) -> [String] {
        let saved = defaults.stringArray(forKey: orderKey) ?? []
        let groupKeys = group.map { $0.key }
        var ordered = saved.filter { groupKeys.contains($0) }
        for k in groupKeys where !ordered.contains(k) { ordered.append(k) }
        return ordered
    }

    func allOrderedKeys() -> [String] {
        let saved = defaults.stringArray(forKey: orderKey) ?? []
        let allKeys = WikiCorpus.domainKeys.map { $0.key }
        var ordered = saved.filter { allKeys.contains($0) }
        for k in allKeys where !ordered.contains(k) { ordered.append(k) }
        return ordered
    }

    func saveOrder(_ keys: [String]) { defaults.set(keys, forKey: orderKey) }
    func isEnabled(_ key: String) -> Bool { YabomishPrefs.domainEnabled(key) }
    func setEnabled(_ key: String, _ val: Bool) { YabomishPrefs.setDomainEnabled(key, val) }
}
