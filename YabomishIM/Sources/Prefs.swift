import Foundation

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
}
