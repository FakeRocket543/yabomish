import Foundation

/// Thin @Observable wrapper over the same UserDefaults keys used by YabomishPrefs (in the IM bundle).
/// All reads/writes go directly through UserDefaults — no stored copies, no duplicated defaults.
@Observable final class PrefsStore {
    @ObservationIgnored private let ud = UserDefaults(suiteName: "com.yabomishim.inputmethod.YabomishIM") ?? .standard

    // MARK: - Suggestion

    #if !MINIMAL
    var suggestEnabled: Bool {
        get { access(keyPath: \.suggestEnabled); return ud.object(forKey: "suggestEnabled") as? Bool ?? true }
        set { withMutation(keyPath: \.suggestEnabled) { ud.set(newValue, forKey: "suggestEnabled") }; postChange() }
    }
    var suggestStrategy: String {
        get { access(keyPath: \.suggestStrategy); return ud.string(forKey: "suggestStrategy") ?? "general" }
        set { withMutation(keyPath: \.suggestStrategy) { ud.set(newValue, forKey: "suggestStrategy") }; postChange() }
    }
    var wordCorpus: String {
        get { access(keyPath: \.wordCorpus); return ud.string(forKey: "wordCorpus") ?? "wiki" }
        set { withMutation(keyPath: \.wordCorpus) { ud.set(newValue, forKey: "wordCorpus") }; postChange() }
    }
    var regionVariant: String {
        get { access(keyPath: \.regionVariant); return ud.string(forKey: "regionVariant") ?? "tw" }
        set { withMutation(keyPath: \.regionVariant) { ud.set(newValue, forKey: "regionVariant") }; postChange() }
    }
    var charSuggest: Bool {
        get { access(keyPath: \.charSuggest); return ud.object(forKey: "charSuggest") as? Bool ?? true }
        set { withMutation(keyPath: \.charSuggest) { ud.set(newValue, forKey: "charSuggest") }; postChange() }
    }
    /// 候選顯示時 Shift+數字鍵輸出："symbol"（預設）／"digit"
    var shiftDigitOutput: String {
        get { access(keyPath: \.shiftDigitOutput); return ud.string(forKey: "shiftDigitOutput") ?? "symbol" }
        set { withMutation(keyPath: \.shiftDigitOutput) { ud.set(newValue, forKey: "shiftDigitOutput") }; postChange() }
    }
    var emojiSuggest: Bool {
        get { access(keyPath: \.emojiSuggest); return ud.object(forKey: "emojiSuggest") as? Bool ?? true }
        set { withMutation(keyPath: \.emojiSuggest) { ud.set(newValue, forKey: "emojiSuggest") }; postChange() }
    }
    var emojiFirst: Bool {
        get { access(keyPath: \.emojiFirst); return ud.object(forKey: "emojiFirst") as? Bool ?? true }
        set { withMutation(keyPath: \.emojiFirst) { ud.set(newValue, forKey: "emojiFirst") }; postChange() }
    }
    /// 聯想列預先反白第一個候選（預設關）。關閉時聯想顯示不反白，
    /// 數字鍵仍可選詞、方向鍵從第一個候選開始導航
    var suggestPreselect: Bool {
        get { access(keyPath: \.suggestPreselect); return ud.object(forKey: "suggestPreselect") as? Bool ?? false }
        set { withMutation(keyPath: \.suggestPreselect) { ud.set(newValue, forKey: "suggestPreselect") }; postChange() }
    }

    // MARK: - Domain ordering

    var domainOrder: [String] {
        get { access(keyPath: \.domainOrder); return ud.stringArray(forKey: "domainOrder") ?? [] }
        set { withMutation(keyPath: \.domainOrder) { ud.set(newValue, forKey: "domainOrder") }; postChange() }
    }
    #endif

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

    /// 介面外觀: "auto"（跟隨系統）/ "light" / "dark"
    var appearanceMode: String {
        get { access(keyPath: \.appearanceMode); return ud.string(forKey: "appearanceMode") ?? "auto" }
        set { withMutation(keyPath: \.appearanceMode) { ud.set(newValue, forKey: "appearanceMode") }; postChange() }
    }
    var fixedAlpha: Double {
        get { access(keyPath: \.fixedAlpha); return ud.object(forKey: "fixedAlpha") as? Double ?? 0.85 }
        set { withMutation(keyPath: \.fixedAlpha) { ud.set(newValue, forKey: "fixedAlpha") }; postChange() }
    }
    var panelPosition: String {
        get { access(keyPath: \.panelPosition); return ud.string(forKey: "panelPosition") ?? "cursor" }
        set { withMutation(keyPath: \.panelPosition) { ud.set(newValue, forKey: "panelPosition") }; postChange() }
    }
    var cursorHorizontal: Bool {
        get { access(keyPath: \.cursorHorizontal); return ud.object(forKey: "cursorHorizontal") as? Bool ?? false }
        set { withMutation(keyPath: \.cursorHorizontal) { ud.set(newValue, forKey: "cursorHorizontal") }; postChange() }
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
    var switchDisplay: String {
        get {
            access(keyPath: \.switchDisplay)
            let v = ud.string(forKey: "switchDisplay") ?? "Yabo"
            return (v == "Yabomish") ? v : "Yabo"   // 舊值（繁中／🦐）遷移為 Yabo
        }
        set { withMutation(keyPath: \.switchDisplay) { ud.set(newValue, forKey: "switchDisplay") }; postChange() }
    }
    var debugMode: Bool {
        get { access(keyPath: \.debugMode); return ud.object(forKey: "debugMode") as? Bool ?? false }
        set { withMutation(keyPath: \.debugMode) { ud.set(newValue, forKey: "debugMode") }; postChange() }
    }
    var highContrast: Bool {
        get { access(keyPath: \.highContrast); return ud.object(forKey: "highContrast") as? Bool ?? false }
        set { withMutation(keyPath: \.highContrast) { ud.set(newValue, forKey: "highContrast") }; postChange() }
    }
    var autoCommit: Bool {
        get { access(keyPath: \.autoCommit); return ud.object(forKey: "autoCommit") as? Bool ?? false }
        set { withMutation(keyPath: \.autoCommit) { ud.set(newValue, forKey: "autoCommit") }; postChange() }
    }
    var showCodeHint: Bool {
        get { access(keyPath: \.showCodeHint); return ud.object(forKey: "showCodeHint") as? Bool ?? false }
        set { withMutation(keyPath: \.showCodeHint) { ud.set(newValue, forKey: "showCodeHint") }; postChange() }
    }
    var homophoneMultiReading: Bool {
        get { access(keyPath: \.homophoneMultiReading); return ud.object(forKey: "homophoneMultiReading") as? Bool ?? false }
        set { withMutation(keyPath: \.homophoneMultiReading) { ud.set(newValue, forKey: "homophoneMultiReading") }; postChange() }
    }
    var homophoneAutoExit: Bool {
        get { access(keyPath: \.homophoneAutoExit); return ud.object(forKey: "homophoneAutoExit") as? Bool ?? false }
        set { withMutation(keyPath: \.homophoneAutoExit) { ud.set(newValue, forKey: "homophoneAutoExit") }; postChange() }
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

    // MARK: - Context Switcher

    #if !MINIMAL
    var currentContext: String? {
        get { access(keyPath: \.currentContext); return ud.string(forKey: "currentContext") }
        set { withMutation(keyPath: \.currentContext) { ud.set(newValue, forKey: "currentContext") }; postChange() }
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
    #endif

    // MARK: - Onboarding

    var hasSeenWelcome: Bool {
        get { access(keyPath: \.hasSeenWelcome); return ud.object(forKey: "hasSeenWelcome") as? Bool ?? false }
        set { withMutation(keyPath: \.hasSeenWelcome) { ud.set(newValue, forKey: "hasSeenWelcome") } }
    }

    func postChange() {
        DistributedNotificationCenter.default().post(name: .init("com.yabomish.prefsChanged"), object: nil)
    }
}
