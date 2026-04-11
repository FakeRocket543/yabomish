import Foundation

/// Protocol to decouple Shared/ engine layer from concrete YabomishPrefs.
/// Inject a test-double to unit-test engines without UserDefaults.
protocol IMEPreferences {
    var autoCommit: Bool { get }
    var fuzzyMatch: Bool { get }
    var showCodeHint: Bool { get }
    var suggestStrategy: String { get }
    var wordCorpus: String { get }
    var charSuggest: Bool { get }
    func domainEnabled(_ key: String) -> Bool
    func domainPriority(_ key: String) -> Int
    var punctuationPairing: Bool { get }
}

/// Bridges the static YabomishPrefs into an instance conforming to IMEPreferences.
final class DefaultPreferences: IMEPreferences {
    static let shared = DefaultPreferences()
    var autoCommit: Bool { YabomishPrefs.autoCommit }
    var fuzzyMatch: Bool { YabomishPrefs.fuzzyMatch }
    var showCodeHint: Bool { YabomishPrefs.showCodeHint }
    var suggestStrategy: String { YabomishPrefs.suggestStrategy }
    var wordCorpus: String { YabomishPrefs.wordCorpus }
    var charSuggest: Bool { YabomishPrefs.charSuggest }
    func domainEnabled(_ key: String) -> Bool { YabomishPrefs.domainEnabled(key) }
    func domainPriority(_ key: String) -> Int { YabomishPrefs.domainPriority(key) }
    var punctuationPairing: Bool { YabomishPrefs.punctuationPairing }
}
