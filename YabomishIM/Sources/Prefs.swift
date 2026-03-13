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
}
