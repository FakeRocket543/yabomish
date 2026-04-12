import Foundation

/// Thin @Observable wrapper over the same UserDefaults keys used by YabomishPrefs (in the IM bundle).
/// All reads/writes go directly through UserDefaults — no stored copies, no duplicated defaults.
@Observable final class PrefsStore {
    @ObservationIgnored private let ud = UserDefaults(suiteName: "com.yabomishim.inputmethod.YabomishIM")!

    // MARK: - Suggestion

    var suggestStrategy: String {
        get { access(keyPath: \.suggestStrategy); return ud.string(forKey: "suggestStrategy") ?? "general" }
        set { withMutation(keyPath: \.suggestStrategy) { ud.set(newValue, forKey: "suggestStrategy") }; postChange() }
    }
    var wordCorpus: String {
        get { access(keyPath: \.wordCorpus); return ud.string(forKey: "wordCorpus") ?? "wiki" }
        set { withMutation(keyPath: \.wordCorpus) { ud.set(newValue, forKey: "wordCorpus") }; postChange() }
    }
    var charSuggest: Bool {
        get { access(keyPath: \.charSuggest); return ud.object(forKey: "charSuggest") as? Bool ?? true }
        set { withMutation(keyPath: \.charSuggest) { ud.set(newValue, forKey: "charSuggest") }; postChange() }
    }

    // MARK: - Domain ordering

    var domainOrder: [String] {
        get { access(keyPath: \.domainOrder); return ud.stringArray(forKey: "domainOrder") ?? [] }
        set { withMutation(keyPath: \.domainOrder) { ud.set(newValue, forKey: "domainOrder") }; postChange() }
    }

    // MARK: - Font sizes

    var fontSize: Double {
        get { access(keyPath: \.fontSize); return ud.object(forKey: "fontSize") as? Double ?? 16.0 }
        set { withMutation(keyPath: \.fontSize) { ud.set(newValue, forKey: "fontSize") }; postChange() }
    }
    var fixedFontSize: Double {
        get { access(keyPath: \.fixedFontSize); return ud.object(forKey: "fixedFontSize") as? Double ?? 18.0 }
        set { withMutation(keyPath: \.fixedFontSize) { ud.set(newValue, forKey: "fixedFontSize") }; postChange() }
    }
    var toastFontSize: Double {
        get { access(keyPath: \.toastFontSize); return ud.object(forKey: "toastFontSize") as? Double ?? 36.0 }
        set { withMutation(keyPath: \.toastFontSize) { ud.set(newValue, forKey: "toastFontSize") }; postChange() }
    }

    // MARK: - Panel

    var fixedAlpha: Double {
        get { access(keyPath: \.fixedAlpha); return ud.object(forKey: "fixedAlpha") as? Double ?? 0.85 }
        set { withMutation(keyPath: \.fixedAlpha) { ud.set(newValue, forKey: "fixedAlpha") }; postChange() }
    }
    var panelPosition: String {
        get { access(keyPath: \.panelPosition); return ud.string(forKey: "panelPosition") ?? "cursor" }
        set { withMutation(keyPath: \.panelPosition) { ud.set(newValue, forKey: "panelPosition") }; postChange() }
    }
    var fixedAlignment: String {
        get { access(keyPath: \.fixedAlignment); return ud.string(forKey: "fixedAlignment") ?? "center" }
        set { withMutation(keyPath: \.fixedAlignment) { ud.set(newValue, forKey: "fixedAlignment") }; postChange() }
    }
    var fixedYOffset: Double {
        get { access(keyPath: \.fixedYOffset); return ud.object(forKey: "fixedYOffset") as? Double ?? 8.0 }
        set { withMutation(keyPath: \.fixedYOffset) { ud.set(newValue, forKey: "fixedYOffset") }; postChange() }
    }

    // MARK: - Toggles

    var showActivateToast: Bool {
        get { access(keyPath: \.showActivateToast); return ud.object(forKey: "showActivateToast") as? Bool ?? true }
        set { withMutation(keyPath: \.showActivateToast) { ud.set(newValue, forKey: "showActivateToast") }; postChange() }
    }
    var iconDirection: String {
        get { access(keyPath: \.iconDirection); return ud.string(forKey: "iconDirection") ?? "left" }
        set { withMutation(keyPath: \.iconDirection) { ud.set(newValue, forKey: "iconDirection") }; postChange() }
    }
    var debugMode: Bool {
        get { access(keyPath: \.debugMode); return ud.object(forKey: "debugMode") as? Bool ?? false }
        set { withMutation(keyPath: \.debugMode) { ud.set(newValue, forKey: "debugMode") }; postChange() }
    }
    var useNewEngine: Bool {
        get { access(keyPath: \.useNewEngine); return ud.object(forKey: "useNewEngine") as? Bool ?? true }
        set { withMutation(keyPath: \.useNewEngine) { ud.set(newValue, forKey: "useNewEngine") }; postChange() }
    }
    var autoCommit: Bool {
        get { access(keyPath: \.autoCommit); return ud.object(forKey: "autoCommit") as? Bool ?? false }
        set { withMutation(keyPath: \.autoCommit) { ud.set(newValue, forKey: "autoCommit") }; postChange() }
    }
    var showCodeHint: Bool {
        get { access(keyPath: \.showCodeHint); return ud.object(forKey: "showCodeHint") as? Bool ?? false }
        set { withMutation(keyPath: \.showCodeHint) { ud.set(newValue, forKey: "showCodeHint") }; postChange() }
    }
    var zhuyinReverseLookup: Bool {
        get { access(keyPath: \.zhuyinReverseLookup); return ud.object(forKey: "zhuyinReverseLookup") as? Bool ?? true }
        set { withMutation(keyPath: \.zhuyinReverseLookup) { ud.set(newValue, forKey: "zhuyinReverseLookup") }; postChange() }
    }
    var homophoneMultiReading: Bool {
        get { access(keyPath: \.homophoneMultiReading); return ud.object(forKey: "homophoneMultiReading") as? Bool ?? false }
        set { withMutation(keyPath: \.homophoneMultiReading) { ud.set(newValue, forKey: "homophoneMultiReading") }; postChange() }
    }
    var fuzzyMatch: Bool {
        get { access(keyPath: \.fuzzyMatch); return ud.object(forKey: "fuzzyMatch") as? Bool ?? true }
        set { withMutation(keyPath: \.fuzzyMatch) { ud.set(newValue, forKey: "fuzzyMatch") }; postChange() }
    }
    var punctuationPairing: Bool {
        get { access(keyPath: \.punctuationPairing); return ud.object(forKey: "punctuationPairing") as? Bool ?? false }
        set { withMutation(keyPath: \.punctuationPairing) { ud.set(newValue, forKey: "punctuationPairing") }; postChange() }
    }
    var syncFolder: String? {
        get { access(keyPath: \.syncFolder); return ud.string(forKey: "syncFolder") }
        set { withMutation(keyPath: \.syncFolder) { ud.set(newValue, forKey: "syncFolder") }; postChange() }
    }

    // MARK: - Domain enable/disable (dynamic keys, tracked)

    var domainStates: [String: Bool] = [:] {
        didSet { /* @Observable tracks this automatically */ }
    }

    func domainEnabled(_ key: String) -> Bool {
        access(keyPath: \.domainStates)
        return domainStates[key] ?? (ud.object(forKey: key) as? Bool ?? false)
    }

    func setDomainEnabled(_ key: String, _ val: Bool) {
        withMutation(keyPath: \.domainStates) {
            domainStates[key] = val
            ud.set(val, forKey: key)
        }
        postChange()
    }

    // MARK: - Onboarding

    var hasSeenWelcome: Bool {
        get { access(keyPath: \.hasSeenWelcome); return ud.object(forKey: "hasSeenWelcome") as? Bool ?? false }
        set { withMutation(keyPath: \.hasSeenWelcome) { ud.set(newValue, forKey: "hasSeenWelcome") } }
    }

    func postChange() {
        DistributedNotificationCenter.default().post(name: .init("com.yabomish.prefsChanged"), object: nil)
    }
}
