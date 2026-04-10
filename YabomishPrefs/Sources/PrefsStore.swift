import Foundation

@Observable final class PrefsStore {
    private let ud = UserDefaults.standard

    var suggestStrategy: String = "general" { didSet { ud.set(suggestStrategy, forKey: "suggestStrategy"); postChange() } }
    var wordCorpus: String = "wiki" { didSet { ud.set(wordCorpus, forKey: "wordCorpus"); postChange() } }
    var charSuggest: Bool = true { didSet { ud.set(charSuggest, forKey: "charSuggest"); postChange() } }
    var domainOrder: [String] = [] { didSet { ud.set(domainOrder, forKey: "domainOrder"); postChange() } }
    var fontSize: Double = 16 { didSet { ud.set(fontSize, forKey: "fontSize"); postChange() } }
    var fixedFontSize: Double = 18 { didSet { ud.set(fixedFontSize, forKey: "fixedFontSize"); postChange() } }
    var fixedAlpha: Double = 0.85 { didSet { ud.set(fixedAlpha, forKey: "fixedAlpha"); postChange() } }
    var toastFontSize: Double = 36 { didSet { ud.set(toastFontSize, forKey: "toastFontSize"); postChange() } }
    var showActivateToast: Bool = true { didSet { ud.set(showActivateToast, forKey: "showActivateToast"); postChange() } }
    var iconDirection: String = "left" { didSet { ud.set(iconDirection, forKey: "iconDirection"); postChange() } }
    var debugMode: Bool = false { didSet { ud.set(debugMode, forKey: "debugMode"); postChange() } }
    var autoCommit: Bool = false { didSet { ud.set(autoCommit, forKey: "autoCommit"); postChange() } }
    var panelPosition: String = "cursor" { didSet { ud.set(panelPosition, forKey: "panelPosition"); postChange() } }
    var fixedAlignment: String = "center" { didSet { ud.set(fixedAlignment, forKey: "fixedAlignment"); postChange() } }
    var fixedYOffset: Double = 8 { didSet { ud.set(fixedYOffset, forKey: "fixedYOffset"); postChange() } }
    var showCodeHint: Bool = false { didSet { ud.set(showCodeHint, forKey: "showCodeHint"); postChange() } }
    var zhuyinReverseLookup: Bool = true { didSet { ud.set(zhuyinReverseLookup, forKey: "zhuyinReverseLookup"); postChange() } }
    var homophoneMultiReading: Bool = false { didSet { ud.set(homophoneMultiReading, forKey: "homophoneMultiReading"); postChange() } }
    var fuzzyMatch: Bool = true { didSet { ud.set(fuzzyMatch, forKey: "fuzzyMatch"); postChange() } }
    var syncFolder: String? = nil { didSet { ud.set(syncFolder, forKey: "syncFolder"); postChange() } }

    init() {
        let ud = self.ud
        if ud.object(forKey: "suggestStrategy") != nil { suggestStrategy = ud.string(forKey: "suggestStrategy") ?? "general" }
        if ud.object(forKey: "wordCorpus") != nil { wordCorpus = ud.string(forKey: "wordCorpus") ?? "wiki" }
        if ud.object(forKey: "charSuggest") != nil { charSuggest = ud.bool(forKey: "charSuggest") }
        if ud.object(forKey: "domainOrder") != nil { domainOrder = ud.stringArray(forKey: "domainOrder") ?? [] }
        if ud.object(forKey: "fontSize") != nil { fontSize = ud.double(forKey: "fontSize") }
        if ud.object(forKey: "fixedFontSize") != nil { fixedFontSize = ud.double(forKey: "fixedFontSize") }
        if ud.object(forKey: "fixedAlpha") != nil { fixedAlpha = ud.double(forKey: "fixedAlpha") }
        if ud.object(forKey: "toastFontSize") != nil { toastFontSize = ud.double(forKey: "toastFontSize") }
        if ud.object(forKey: "showActivateToast") != nil { showActivateToast = ud.bool(forKey: "showActivateToast") }
        if ud.object(forKey: "iconDirection") != nil { iconDirection = ud.string(forKey: "iconDirection") ?? "left" }
        if ud.object(forKey: "debugMode") != nil { debugMode = ud.bool(forKey: "debugMode") }
        if ud.object(forKey: "autoCommit") != nil { autoCommit = ud.bool(forKey: "autoCommit") }
        if ud.object(forKey: "panelPosition") != nil { panelPosition = ud.string(forKey: "panelPosition") ?? "cursor" }
        if ud.object(forKey: "fixedAlignment") != nil { fixedAlignment = ud.string(forKey: "fixedAlignment") ?? "center" }
        if ud.object(forKey: "fixedYOffset") != nil { fixedYOffset = ud.double(forKey: "fixedYOffset") }
        if ud.object(forKey: "showCodeHint") != nil { showCodeHint = ud.bool(forKey: "showCodeHint") }
        if ud.object(forKey: "zhuyinReverseLookup") != nil { zhuyinReverseLookup = ud.bool(forKey: "zhuyinReverseLookup") }
        if ud.object(forKey: "homophoneMultiReading") != nil { homophoneMultiReading = ud.bool(forKey: "homophoneMultiReading") }
        if ud.object(forKey: "fuzzyMatch") != nil { fuzzyMatch = ud.bool(forKey: "fuzzyMatch") }
        syncFolder = ud.string(forKey: "syncFolder")
    }

    func domainEnabled(_ key: String) -> Bool {
        ud.object(forKey: key) as? Bool ?? false
    }

    func setDomainEnabled(_ key: String, _ val: Bool) {
        ud.set(val, forKey: key)
        postChange()
    }

    func postChange() {
        DistributedNotificationCenter.default().post(name: .init("com.yabomish.prefsChanged"), object: nil)
    }
}
