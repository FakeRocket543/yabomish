import Foundation
import Cocoa

/// User preferences stored in UserDefaults
struct YabomishPrefs {
    /// Shared defaults using the same suite as YabomishPrefs, so that the
    /// input method and the preferences app read/write the same keys.
    private static let _standard = UserDefaults.standard
    static let defaults = UserDefaults(suiteName: "com.yabomishim.inputmethod.YabomishIM") ?? _standard

    // MARK: - 偏好快照（按鍵熱路徑效能）

    /// 所有純量偏好的內部快照；欄位預設值與各屬性的 fallback 完全一致。
    /// 讀取走快照（uncontended NSLock 約數十 ns），setter 寫入 defaults 後
    /// 立即重讀替換快照；跨行程（YabomishPrefs app）的變更則由
    /// "com.yabomish.prefsChanged" 廣播觸發重讀。
    private struct Snapshot {
        var autoCommit = false
        var panelPosition = "cursor"
        var cursorHorizontal = false
        var fixedAlignment = "center"
        var fixedAlpha: CGFloat = 0.85
        var fixedYOffset: CGFloat = 8.0
        var fontSize: CGFloat = 16.0
        var fixedFontSize: CGFloat = 18.0
        var showCodeHint = false
        var toastFontSize: CGFloat = 36.0
        var showActivateToast = true
        var switchDisplay = "Yabo"
        var appearanceMode = "auto"
        var iconDirection = "left"
        var homophoneMultiReading = false
        var homophoneAutoExit = false
        var suggestEnabled = true
        var fuzzyMatch = true
        var suggestStrategy = "general"
        var wordCorpus = "wiki"
        var regionVariant = "tw"
        var charSuggest = true
        var emojiSuggest = true
        var emojiFirst = true
        var suggestPreselect = false
        var corpusVariant = "lite"
        var shiftDigitOutput = "symbol"
        #if os(iOS)
        var punctuationPairing = true
        #else
        var punctuationPairing = false
        #endif
        var debugMode = false
        var highContrast = false
        var syncFolder: String?
        #if !MINIMAL
        var currentContext: String?
        #endif
    }

    /// 保護 _snapshot 讀取與替換的鎖。
    private static let snapshotLock = NSLock()

    /// 偏好快照。static var 的初始值為 lazy + 執行緒安全，
    /// 首次存取時才呼叫 loadSnapshot() 讀取一次 defaults。
    private static var _snapshot: Snapshot = loadSnapshot()

    /// 從 UserDefaults 一次性讀取所有偏好建立快照（fallback 與原本各 getter 相同）。
    private static func loadSnapshot() -> Snapshot {
        #if os(macOS)
        // 首次存取快照時順帶註冊跨行程通知；static let 保證只註冊一次。
        _ = prefsChangedObserver
        #endif
        var s = Snapshot()
        s.autoCommit = defaults.object(forKey: "autoCommit") as? Bool ?? false
        s.panelPosition = defaults.string(forKey: "panelPosition") ?? "cursor"
        s.cursorHorizontal = defaults.object(forKey: "cursorHorizontal") as? Bool ?? false
        s.fixedAlignment = defaults.string(forKey: "fixedAlignment") ?? "center"
        s.fixedAlpha = CGFloat(defaults.object(forKey: "fixedAlpha") as? Double ?? 0.85)
        s.fixedYOffset = CGFloat(defaults.object(forKey: "fixedYOffset") as? Double ?? 8.0)
        s.fontSize = CGFloat(defaults.object(forKey: "fontSize") as? Double ?? 16.0)
        s.fixedFontSize = CGFloat(defaults.object(forKey: "fixedFontSize") as? Double ?? 18.0)
        s.showCodeHint = defaults.object(forKey: "showCodeHint") as? Bool ?? false
        s.toastFontSize = CGFloat(defaults.object(forKey: "toastFontSize") as? Double ?? 36.0)
        s.showActivateToast = defaults.object(forKey: "showActivateToast") as? Bool ?? true
        s.switchDisplay = defaults.string(forKey: "switchDisplay") ?? "Yabo"
        s.appearanceMode = defaults.string(forKey: "appearanceMode") ?? "auto"
        s.iconDirection = defaults.string(forKey: "iconDirection") ?? "left"
        s.homophoneMultiReading = defaults.object(forKey: "homophoneMultiReading") as? Bool ?? false
        s.homophoneAutoExit = defaults.object(forKey: "homophoneAutoExit") as? Bool ?? false
        s.suggestEnabled = defaults.object(forKey: "suggestEnabled") as? Bool ?? true
        s.fuzzyMatch = defaults.object(forKey: "fuzzyMatch") as? Bool ?? true
        s.suggestStrategy = defaults.string(forKey: "suggestStrategy") ?? "general"
        s.wordCorpus = defaults.string(forKey: "wordCorpus") ?? "wiki"
        s.regionVariant = defaults.string(forKey: "regionVariant") ?? "tw"
        s.charSuggest = defaults.object(forKey: "charSuggest") as? Bool ?? true
        s.emojiSuggest = defaults.object(forKey: "emojiSuggest") as? Bool ?? true
        s.emojiFirst = defaults.object(forKey: "emojiFirst") as? Bool ?? true
        s.suggestPreselect = defaults.object(forKey: "suggestPreselect") as? Bool ?? false
        s.corpusVariant = defaults.string(forKey: "corpusVariant") ?? "lite"
        s.shiftDigitOutput = defaults.string(forKey: "shiftDigitOutput") ?? "symbol"
        #if os(iOS)
        s.punctuationPairing = defaults.object(forKey: "punctuationPairing") as? Bool ?? true
        #else
        s.punctuationPairing = defaults.object(forKey: "punctuationPairing") as? Bool ?? false
        #endif
        s.debugMode = defaults.object(forKey: "debugMode") as? Bool ?? false
        s.highContrast = defaults.object(forKey: "highContrast") as? Bool ?? false
        s.syncFolder = defaults.string(forKey: "syncFolder")
        #if !MINIMAL
        s.currentContext = defaults.string(forKey: "currentContext")
        #endif
        return s
    }

    /// 重讀 defaults 並替換快照。讀取與替換同在鎖內：並發 refresh 依完成
    /// 序序列化，後完成者必讀到較新的 defaults，不會以舊值蓋回新值。
    /// setter 寫入後立即呼叫，讓同行程的變更（如引擎的 ,,SG 切換）即刻生效。
    private static func refreshSnapshot() {
        snapshotLock.lock()
        _snapshot = loadSnapshot()
        snapshotLock.unlock()
    }

    #if os(macOS)
    /// 跨行程偏好變更通知：YabomishPrefs app 寫入 defaults 後廣播此名稱。
    /// 以 static let 的 lazy 執行緒安全初始化保證整個程式生命週期只註冊一次。
    private static let prefsChangedObserver: Void = {
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.yabomish.prefsChanged"), object: nil, queue: .main
        ) { _ in YabomishPrefs.refreshSnapshot() }
    }()
    #endif

    /// Auto-commit when single candidate and code cannot extend further
    static var autoCommit: Bool {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.autoCommit
        }
        set {
            defaults.set(newValue, forKey: "autoCommit")
            refreshSnapshot()
        }
    }

    /// Candidate panel position: "cursor" (near input) or "fixed" (screen bottom-center)
    static var panelPosition: String {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.panelPosition
        }
        set {
            defaults.set(newValue, forKey: "panelPosition")
            refreshSnapshot()
        }
    }

    /// Cursor mode layout: when true, display candidates horizontally instead of vertically
    static var cursorHorizontal: Bool {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.cursorHorizontal
        }
        set {
            defaults.set(newValue, forKey: "cursorHorizontal")
            refreshSnapshot()
        }
    }

    // MARK: - Fixed-mode panel settings

    /// Horizontal alignment: "center", "left", "right"
    static var fixedAlignment: String {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.fixedAlignment
        }
        set {
            defaults.set(newValue, forKey: "fixedAlignment")
            refreshSnapshot()
        }
    }

    /// Panel opacity 0.3–1.0
    static var fixedAlpha: CGFloat {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.fixedAlpha
        }
        set {
            defaults.set(Double(newValue), forKey: "fixedAlpha")
            refreshSnapshot()
        }
    }

    /// Y offset above Dock (points)
    static var fixedYOffset: CGFloat {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.fixedYOffset
        }
        set {
            defaults.set(Double(newValue), forKey: "fixedYOffset")
            refreshSnapshot()
        }
    }

    // MARK: - Font size

    /// Candidate panel font size (cursor mode)
    static var fontSize: CGFloat {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.fontSize
        }
        set {
            defaults.set(Double(newValue), forKey: "fontSize")
            refreshSnapshot()
        }
    }

    /// Fixed-mode font size
    static var fixedFontSize: CGFloat {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.fixedFontSize
        }
        set {
            defaults.set(Double(newValue), forKey: "fixedFontSize")
            refreshSnapshot()
        }
    }

    // MARK: - Learning aids

    /// Show Boshiamy code after committing a character
    static var showCodeHint: Bool {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.showCodeHint
        }
        set {
            defaults.set(newValue, forKey: "showCodeHint")
            refreshSnapshot()
        }
    }

    // MARK: - Mode toast

    /// Toast font size
    static var toastFontSize: CGFloat {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.toastFontSize
        }
        set {
            defaults.set(Double(newValue), forKey: "toastFontSize")
            refreshSnapshot()
        }
    }

    /// 切換進 Yabomish 時顯示模式 toast
    static var showActivateToast: Bool {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.showActivateToast
        }
        set {
            defaults.set(newValue, forKey: "showActivateToast")
            refreshSnapshot()
        }
    }

    /// 切換顯示（切入提示 / 狀態列名稱）: "繁中" / "Yabomish" / "🦐"
    static var switchDisplay: String {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.switchDisplay
        }
        set {
            defaults.set(newValue, forKey: "switchDisplay")
            refreshSnapshot()
        }
    }

    // MARK: - Appearance

    /// 介面外觀（候選字窗／提示窗）: "auto"（跟隨系統）/ "light" / "dark"
    static var appearanceMode: String {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.appearanceMode
        }
        set {
            defaults.set(newValue, forKey: "appearanceMode")
            refreshSnapshot()
        }
    }

    /// 浮動視窗套用的 NSAppearance；nil = 跟隨系統
    static var resolvedAppearance: NSAppearance? {
        switch appearanceMode {
        case "light": return NSAppearance(named: .aqua)
        case "dark":  return NSAppearance(named: .darkAqua)
        default:      return nil
        }
    }

    static var iconDirection: String {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.iconDirection
        }
        set {
            defaults.set(newValue, forKey: "iconDirection")
            refreshSnapshot()
        }
    }

    /// 同音字查詢包含多音字的罕見讀音（如「色」的 ㄕㄜˋ）
    static var homophoneMultiReading: Bool {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.homophoneMultiReading
        }
        set {
            defaults.set(newValue, forKey: "homophoneMultiReading")
            refreshSnapshot()
        }
    }

    /// 同音字模式：選字送出後自動退出（預設關閉，維持既有行為）
    static var homophoneAutoExit: Bool {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.homophoneAutoExit
        }
        set {
            defaults.set(newValue, forKey: "homophoneAutoExit")
            refreshSnapshot()
        }
    }

    /// Deprecated — 舊版用 bigramSuggest 控制所有聯想，已遷移。
    static func migrateLegacyPrefs() {
        // One-time migration: copy old standard-only values into the shared suite
        // so existing users keep their settings when the IM moves to the suite.
        let migrationFlag = "yabomishMigratedToSuite_v1"
        if !_standard.bool(forKey: migrationFlag) {
            let knownKeys = [
                "autoCommit", "panelPosition", "fixedAlignment", "fixedAlpha", "fixedYOffset",
                "fontSize", "fixedFontSize", "showCodeHint", "zhuyinReverseLookup",
                "toastFontSize", "showActivateToast", "menuBarLabel", "iconDirection",
                "appearanceMode",
                "homophoneMultiReading", "homophoneAutoExit", "suggestEnabled", "useNewEngine",
                "fuzzyMatch", "suggestStrategy", "wordCorpus", "regionVariant", "charSuggest",
                "emojiSuggest", "emojiFirst", "suggestPreselect", "corpusVariant", "shiftDigitOutput",
                "punctuationPairing", "debugMode", "highContrast", "syncFolder", "currentContext",
                "domainOrder"
            ]
            for key in knownKeys {
                if defaults.object(forKey: key) == nil, let value = _standard.object(forKey: key) {
                    defaults.set(value, forKey: key)
                }
            }
            for (key, value) in _standard.dictionaryRepresentation() where key.hasPrefix("domain_") {
                if defaults.object(forKey: key) == nil {
                    defaults.set(value, forKey: key)
                }
            }
            // 上面是直接寫 defaults（未走 setter），需手動重讀讓快照同步。
            refreshSnapshot()
            _standard.set(true, forKey: migrationFlag)
        }

        if let old = defaults.object(forKey: "bigramSuggest") as? Bool, old {
            if defaults.object(forKey: "charSuggest") == nil { charSuggest = true }
        }
        for key in ["bigramSuggest", "communityBoost", "contextMode", "wordSuggest", "chengyuFirst"] {
            defaults.removeObject(forKey: key)
            _standard.removeObject(forKey: key)
        }
    }

    // MARK: - Suggestion system

    /// Master switch for suggestion system
    static var suggestEnabled: Bool {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.suggestEnabled
        }
        set {
            defaults.set(newValue, forKey: "suggestEnabled")
            refreshSnapshot()
        }
    }

    /// Fuzzy match: try adjacent-key substitution when no candidates found
    static var fuzzyMatch: Bool {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.fuzzyMatch
        }
        set {
            defaults.set(newValue, forKey: "fuzzyMatch")
            refreshSnapshot()
        }
    }

    /// 策略：general（詞級→詞庫→字級）/ domain（詞庫→詞級→字級）/ char（字級→詞級→詞庫）
    static var suggestStrategy: String {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.suggestStrategy
        }
        set {
            defaults.set(newValue, forKey: "suggestStrategy")
            refreshSnapshot()
        }
    }

    /// 詞級語料：moedict / wiki / news
    static var wordCorpus: String {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.wordCorpus
        }
        set {
            defaults.set(newValue, forKey: "wordCorpus")
            refreshSnapshot()
        }
    }

    /// 地區用詞：tw / cn
    static var regionVariant: String {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.regionVariant
        }
        set {
            defaults.set(newValue, forKey: "regionVariant")
            refreshSnapshot()
        }
    }

    /// Char-level suggestions (bigram, trigram)
    static var charSuggest: Bool {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.charSuggest
        }
        set {
            defaults.set(newValue, forKey: "charSuggest")
            refreshSnapshot()
        }
    }

    /// 聯想列是否包含 Emoji 建議（Unicode CLDR 字元對照）
    static var emojiSuggest: Bool {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.emojiSuggest
        }
        set {
            defaults.set(newValue, forKey: "emojiSuggest")
            refreshSnapshot()
        }
    }

    /// Emoji 建議位置：true = 排聯想列最前（既有行為）；false = 文字聯想優先，有剩餘空間才顯示
    static var emojiFirst: Bool {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.emojiFirst
        }
        set {
            defaults.set(newValue, forKey: "emojiFirst")
            refreshSnapshot()
        }
    }

    /// 語料下載等級（網路版）："lite"（預設，基礎語料約 15MB）或 "full"（全量語料＋專業詞典）。
    /// 由安裝程式在安裝時寫入；只有純聯想顯示資料不存在時的下載行為會參考它。
    static var corpusVariant: String {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.corpusVariant
        }
        set {
            defaults.set(newValue, forKey: "corpusVariant")
            refreshSnapshot()
        }
    }

    /// 聯想列預先反白第一個候選（預設關：純聯想顯示不反白，升級使用者如偏好舊觀感可開啟）。
    /// 關閉時數字鍵仍可直接選詞、方向鍵從第一個候選開始導航。
    /// 僅影響純聯想顯示（組字已空）；組字候選一律反白第一個，不受此偏好影響。
    static var suggestPreselect: Bool {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.suggestPreselect
        }
        set {
            defaults.set(newValue, forKey: "suggestPreselect")
            refreshSnapshot()
        }
    }

    /// 候選／聯想顯示時 Shift+數字鍵的輸出："symbol"（預設，!@#$%^&*()）或 "digit"（1234567890）。
    /// 僅影響候選顯示中；idle 狀態的 Shift+數字恆為符號，組字中的 Shift+8 萬用碼不受此偏好影響。
    static var shiftDigitOutput: String {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.shiftDigitOutput
        }
        set {
            defaults.set(newValue, forKey: "shiftDigitOutput")
            refreshSnapshot()
        }
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
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.punctuationPairing
        }
        set {
            defaults.set(newValue, forKey: "punctuationPairing")
            refreshSnapshot()
        }
    }


    /// Debug mode: write detailed logs to AppConstants.sharedDir/debug.log
    static var debugMode: Bool {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.debugMode
        }
        set {
            defaults.set(newValue, forKey: "debugMode")
            refreshSnapshot()
        }
    }

    /// 候選字高對比模式：加粗 + 文字陰影
    static var highContrast: Bool {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.highContrast
        }
        set {
            defaults.set(newValue, forKey: "highContrast")
            refreshSnapshot()
        }
    }

    /// 同步資料夾（nil = 不開啟，使用本機 AppConstants.sharedDir）— 同步 freq.json + tables/*.txt
    static var syncFolder: String? {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.syncFolder
        }
        set {
            defaults.set(newValue, forKey: "syncFolder")
            refreshSnapshot()
        }
    }

    // MARK: - Context Switcher

    #if !MINIMAL
    static var currentContext: String? {
        get {
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            return _snapshot.currentContext
        }
        set {
            defaults.set(newValue, forKey: "currentContext")
            refreshSnapshot()
        }
    }

    static func applyProfile(_ profile: ContextProfile) {
        suggestEnabled = profile.suggestEnabled
        suggestStrategy = profile.suggestStrategy
        charSuggest = profile.charSuggest
        wordCorpus = profile.wordCorpus
        regionVariant = profile.regionVariant
        fuzzyMatch = profile.fuzzyMatch
        autoCommit = profile.autoCommit
        defaults.set(profile.domainOrder, forKey: "domainOrder")
        // Clear all domain toggles first, then apply profile's
        for (key, _) in defaults.dictionaryRepresentation() where key.hasPrefix("domain_") && !key.hasSuffix("_pri") {
            defaults.set(false, forKey: key)
        }
        for (key, val) in profile.domainEnabled {
            setDomainEnabled(key, val)
        }
        currentContext = profile.code
    }
    #endif
}
