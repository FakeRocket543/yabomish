import Foundation

/// `,,X` context-profile command family (non-MINIMAL builds).
/// Extracted from InputEngine's comma dispatch to keep the engine a pure state machine.
/// All actions return an optional toast message; profile switching also reports the
/// profile's input mode so the engine can sync its state.
#if !MINIMAL
enum ContextProfileCommands {
    struct Result {
        let toast: String
        /// Input mode stored in the applied profile (engine syncs _inputMode when non-nil).
        let inputMode: InputEngine.InputMode?
    }

    /// Dispatch an `,,X<sub>` command. Returns nil when `sub` is not a context command
    /// (caller falls through to unknown-command handling).
    static func dispatch(sub: String) -> Result? {
        if sub == "s" {
            guard let code = YabomishPrefs.currentContext,
                  var profile = ContextProfile.load(code: code) else {
                return Result(toast: "尚未選擇語境，無法儲存", inputMode: nil)
            }
            let snap = ContextProfile.snapshotCurrent()
            profile.inputMode = snap.inputMode
            profile.suggestEnabled = snap.suggestEnabled
            profile.suggestStrategy = snap.suggestStrategy
            profile.charSuggest = snap.charSuggest
            profile.wordCorpus = snap.wordCorpus
            profile.regionVariant = snap.regionVariant
            profile.fuzzyMatch = snap.fuzzyMatch
            profile.autoCommit = snap.autoCommit
            profile.domainOrder = snap.domainOrder
            profile.domainEnabled = snap.domainEnabled
            profile.save()
            return Result(toast: "\(profile.icon) \(profile.name) 已儲存", inputMode: nil)
        }
        if sub == "i" {
            if let code = YabomishPrefs.currentContext,
               let profile = ContextProfile.load(code: code) {
                return Result(toast: "\(profile.icon) \(profile.name)", inputMode: nil)
            }
            return Result(toast: "無語境（使用預設設定）", inputMode: nil)
        }
        if sub == "rs" {
            if let profile = ContextProfile.load(code: "df") {
                YabomishPrefs.applyProfile(profile)
                DomainOrderManager.shared.saveOrder(profile.domainOrder)
                return Result(toast: "\(profile.icon) \(profile.name)", inputMode: .t)
            }
            YabomishPrefs.currentContext = nil
            return Result(toast: "語境已重置", inputMode: .t)
        }
        if sub.count == 2, let profile = ContextProfile.load(code: sub) {
            YabomishPrefs.applyProfile(profile)
            DomainOrderManager.shared.saveOrder(profile.domainOrder)
            let mode = InputEngine.InputMode(rawValue: profile.inputMode)
            return Result(toast: "\(profile.icon) \(profile.name)", inputMode: mode)
        }
        if sub.count == 2 {
            return Result(toast: "未知語境 ,,X\(sub.uppercased())", inputMode: nil)
        }
        return Result(toast: "語境碼需 2 字母", inputMode: nil)
    }
}
#endif
