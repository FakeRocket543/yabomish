import Foundation

#if !MINIMAL
/// Plugin-style text snippets: short codes expand to long text.
/// Loads from four sources (later override earlier):
/// 1. Default bundle snippets in Resources/Plugins/
/// 2. Plugin folders in ~/Library/Application Support/Yabomish/Plugins/
/// 3. commands.json entries of type "text" (cross-platform sync contract)
/// 4. user_snippets.json in the shared directory
final class UserSnippets {
    static let shared = UserSnippets()
    private var snippets: [String: String] = [:]

    private init() { reload() }

    /// Look up the full expansion for a snippet code.
    func expansion(for code: String) -> String? {
        snippets[code]
    }

    /// Return true if `code` is a prefix of any *longer* known snippet.
    /// This is used by the engine to decide whether to keep accepting keystrokes
    /// past the normal CIN maxCodeLength while the user is typing a long snippet.
    func hasPrefix(_ code: String) -> Bool {
        snippets.keys.contains { $0.count > code.count && $0.hasPrefix(code) }
    }

    /// Return a display label for the candidate panel.
    func display(for code: String) -> String? {
        guard let expansion = snippets[code] else { return nil }
        if expansion.count <= 32 { return "📝 \(expansion)" }
        let prefix = expansion.prefix(29)
        return "📝 \(prefix)..."
    }

    /// Reload all snippet sources.
    func reload() {
        var merged: [String: String] = [:]

        for (code, text) in defaultSnippets() {
            merged[code] = text
        }
        for (code, text) in pluginSnippets() {
            merged[code] = text
        }
        for (code, text) in commandSnippets() {
            merged[code] = text
        }
        for (code, text) in userSnippets() {
            merged[code] = text
        }

        snippets = merged
    }

    // MARK: - Sources

    private func userSnippetsPath() -> String {
        AppConstants.sharedDir + "/user_snippets.json"
    }

    private func pluginsDirectory() -> String {
        AppConstants.sharedDir + "/Plugins"
    }

    /// 1. Built-in default snippets shipped with the app bundle.
    ///    - Resources/Plugins/bosh-snippets.json (legacy)
    ///    - Resources/Plugins/<name>/snippets.json (new plugin bundles)
    private func defaultSnippets() -> [String: String] {
        var merged: [String: String] = [:]

        // Legacy single-file default snippets
        if let url = Bundle.main.url(forResource: "bosh-snippets", withExtension: "json", subdirectory: "Plugins"),
           let data = try? Data(contentsOf: url),
           let dict = decodeSnippets(data) {
            for (code, text) in dict { merged[code] = text }
        }

        // New plugin bundles: Plugins/<name>/snippets.json
        let fm = FileManager.default
        if let resourceURL = Bundle.main.resourceURL,
           let entries = try? fm.contentsOfDirectory(at: resourceURL.appendingPathComponent("Plugins"), includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for dir in entries where dir.hasDirectoryPath {
                let file = dir.appendingPathComponent("snippets.json")
                guard let data = try? Data(contentsOf: file),
                      let dict = decodeSnippets(data) else { continue }
                for (code, text) in dict { merged[code] = text }
            }
        }

        return merged
    }

    /// 2. Plugin folders: Plugins/<name>/snippets.json
    private func pluginSnippets() -> [String: String] {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: pluginsDirectory())
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        else { return [:] }

        var merged: [String: String] = [:]
        for dir in entries where dir.hasDirectoryPath {
            let file = dir.appendingPathComponent("snippets.json")
            guard let data = try? Data(contentsOf: file),
                  let dict = decodeSnippets(data)
            else { continue }
            for (code, text) in dict {
                merged[code] = text
            }
        }
        return merged
    }

    /// 3. commands.json text entries (already synced cross-platform).
    private func commandSnippets() -> [String: String] {
        let path = AppConstants.sharedDir + "/commands.json"
        guard let data = FileManager.default.contents(atPath: path),
              let dict = try? JSONDecoder().decode([String: CommaCommandRunner.Command].self, from: data)
        else { return [:] }
        return dict.compactMapValues { $0.type == "text" ? $0.text : nil }
    }

    /// 4. User's own snippets file.
    private func userSnippets() -> [String: String] {
        let path = userSnippetsPath()
        guard let data = FileManager.default.contents(atPath: path) else { return [:] }
        return decodeSnippets(data) ?? [:]
    }

    private func decodeSnippets(_ data: Data) -> [String: String]? {
        try? JSONDecoder().decode([String: String].self, from: data)
    }
}
#endif
