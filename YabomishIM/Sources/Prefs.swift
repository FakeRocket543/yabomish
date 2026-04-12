import Foundation
import Cocoa

/// User preferences stored in UserDefaults
struct YabomishPrefs {
    private static let defaults = UserDefaults.standard

    /// Auto-commit when single candidate and code cannot extend further
    static var autoCommit: Bool {
        get { defaults.object(forKey: "autoCommit") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "autoCommit") }
    }

    /// Candidate panel position: "cursor" (near input) or "fixed" (screen bottom-center)
    static var panelPosition: String {
        get { defaults.string(forKey: "panelPosition") ?? "cursor" }
        set { defaults.set(newValue, forKey: "panelPosition") }
    }

    // MARK: - Fixed-mode panel settings

    /// Horizontal alignment: "center", "left", "right"
    static var fixedAlignment: String {
        get { defaults.string(forKey: "fixedAlignment") ?? "center" }
        set { defaults.set(newValue, forKey: "fixedAlignment") }
    }

    /// Panel opacity 0.3–1.0
    static var fixedAlpha: CGFloat {
        get {
            let v = defaults.object(forKey: "fixedAlpha") as? Double ?? 0.85
            return CGFloat(v)
        }
        set { defaults.set(Double(newValue), forKey: "fixedAlpha") }
    }

    /// Y offset above Dock (points)
    static var fixedYOffset: CGFloat {
        get { CGFloat(defaults.object(forKey: "fixedYOffset") as? Double ?? 8.0) }
        set { defaults.set(Double(newValue), forKey: "fixedYOffset") }
    }

    // MARK: - Font size

    /// Candidate panel font size (cursor mode)
    static var fontSize: CGFloat {
        get { CGFloat(defaults.object(forKey: "fontSize") as? Double ?? 16.0) }
        set { defaults.set(Double(newValue), forKey: "fontSize") }
    }

    /// Fixed-mode font size
    static var fixedFontSize: CGFloat {
        get { CGFloat(defaults.object(forKey: "fixedFontSize") as? Double ?? 18.0) }
        set { defaults.set(Double(newValue), forKey: "fixedFontSize") }
    }

    // MARK: - Learning aids

    /// Show Boshiamy code after committing a character
    static var showCodeHint: Bool {
        get { defaults.object(forKey: "showCodeHint") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showCodeHint") }
    }

    /// Zhuyin reverse lookup mode (type zhuyin → see Boshiamy code)
    static var zhuyinReverseLookup: Bool {
        get { defaults.object(forKey: "zhuyinReverseLookup") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "zhuyinReverseLookup") }
    }

    // MARK: - Mode toast

    /// Toast font size
    static var toastFontSize: CGFloat {
        get { CGFloat(defaults.object(forKey: "toastFontSize") as? Double ?? 36.0) }
        set { defaults.set(Double(newValue), forKey: "toastFontSize") }
    }

    /// 切換進 Yabomish 時顯示模式 toast
    static var showActivateToast: Bool {
        get { defaults.object(forKey: "showActivateToast") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showActivateToast") }
    }

    /// 狀態列顯示名稱: "yabo" / "yabomish"
    static var menuBarLabel: String {
        get { defaults.string(forKey: "menuBarLabel") ?? "yabomish" }
        set { defaults.set(newValue, forKey: "menuBarLabel") }
    }
    static var iconDirection: String {
        get { defaults.string(forKey: "iconDirection") ?? "left" }
        set { defaults.set(newValue, forKey: "iconDirection") }
    }

    /// 同音字查詢包含多音字的罕見讀音（如「色」的 ㄕㄜˋ）
    static var homophoneMultiReading: Bool {
        get { defaults.object(forKey: "homophoneMultiReading") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "homophoneMultiReading") }
    }

    /// Deprecated — 舊版用 bigramSuggest 控制所有聯想，已遷移。
    static func migrateLegacyPrefs() {
        if let old = defaults.object(forKey: "bigramSuggest") as? Bool, old {
            if defaults.object(forKey: "charSuggest") == nil { charSuggest = true }
        }
        for key in ["bigramSuggest", "communityBoost", "contextMode", "wordSuggest", "chengyuFirst"] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Suggestion system

    /// Master switch for suggestion system
    static var suggestEnabled: Bool {
        get { defaults.object(forKey: "suggestEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "suggestEnabled") }
    }

    /// Use the new shared InputEngine (from iOS). Set to false to use legacy controller.
    static var useNewEngine: Bool {
        get { defaults.object(forKey: "useNewEngine") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "useNewEngine") }
    }

    /// Fuzzy match: try adjacent-key substitution when no candidates found
    static var fuzzyMatch: Bool {
        get { defaults.object(forKey: "fuzzyMatch") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "fuzzyMatch") }
    }

    /// 策略：general（詞級→詞庫→字級）/ domain（詞庫→詞級→字級）/ char（字級→詞級→詞庫）
    static var suggestStrategy: String {
        get { defaults.string(forKey: "suggestStrategy") ?? "general" }
        set { defaults.set(newValue, forKey: "suggestStrategy") }
    }

    /// 詞級語料：moedict / wiki / news
    static var wordCorpus: String {
        get { defaults.string(forKey: "wordCorpus") ?? "wiki" }
        set { defaults.set(newValue, forKey: "wordCorpus") }
    }

    /// Char-level suggestions (bigram, trigram)
    static var charSuggest: Bool {
        get { defaults.object(forKey: "charSuggest") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "charSuggest") }
    }

    /// Domain dictionary toggle (per-domain key, e.g. "domain_it")
    static func domainEnabled(_ key: String) -> Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }
    static func setDomainEnabled(_ key: String, _ value: Bool) {
        defaults.set(value, forKey: key)
    }

    /// Domain priority: smaller = higher priority (like nice). Default 0.
    static func domainPriority(_ key: String) -> Int {
        defaults.object(forKey: key + "_pri") as? Int ?? 0
    }
    static func setDomainPriority(_ key: String, _ value: Int) {
        defaults.set(value, forKey: key + "_pri")
    }

    /// 標點配對：打「自動補」（iOS 風格）。關閉則各別輸出（macOS 傳統）。
    static var punctuationPairing: Bool {
        get {
            #if os(iOS)
            return defaults.object(forKey: "punctuationPairing") as? Bool ?? true
            #else
            return defaults.object(forKey: "punctuationPairing") as? Bool ?? false
            #endif
        }
        set { defaults.set(newValue, forKey: "punctuationPairing") }
    }

    /// Debug mode: write detailed logs to ~/Library/YabomishIM/debug.log
    static var debugMode: Bool {
        get { defaults.object(forKey: "debugMode") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "debugMode") }
    }

    /// 同步資料夾（nil = 不開啟，使用本機 ~/Library/YabomishIM/）— 同步 freq.json + tables/*.txt
    static var syncFolder: String? {
        get { defaults.string(forKey: "syncFolder") }
        set { defaults.set(newValue, forKey: "syncFolder") }
    }
}
