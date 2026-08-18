import Foundation

/// 外部指令 commands.json — v2 schema（三平台共用契約）
///
/// ```json
/// {
///   "auau": { "type": "text",  "text": "sudo apt update && sudo apt upgrade" },
///   "ss":   { "type": "shell", "run": "~/.../yabomish_capture.sh screen" },
///   "saf":  { "type": "open",  "app": "Safari" }
/// }
/// ```
///
/// - `text`  → 展開成文字直接送出（macOS/iOS/Android 三平台）
/// - `shell` → 執行 shell 指令（僅 macOS）
/// - `open`  → 開啟 app（僅 macOS）
enum CommaCommandRunner {

    struct Command: Decodable {
        let type: String
        let app: String?
        let run: String?
        let text: String?
    }
    private(set) static var commands: [String: Command] = [:]

    static var configPath: String {
        AppConstants.sharedDir + "/commands.json"
    }
    static func reload() { reload(path: configPath) }

    /// Load commands from an explicit path (tests / sync import).
    static func reload(path: String) {
        guard let data = FileManager.default.contents(atPath: path),
              let dict = try? JSONDecoder().decode([String: Command].self, from: data)
        else { commands = [:]; return }
        commands = dict
    }

    /// 純文字展開（跨平台）：``,,auau`` → 展開文字。無需處理程序、沙盒內零風險。
    /// 回傳 nil 表示此指令不是 text 型別（或不存在），交由後續 pipeline 處理。
    static func expandText(_ cmd: String) -> String? {
        guard let command = commands[cmd], command.type == "text" else { return nil }
        return command.text
    }

    /// Try to execute a platform command (shell/open, macOS-only). Returns true if matched.
    static func tryExecute(_ cmd: String, toast: @escaping (String) -> Void) -> Bool {
        #if os(macOS)
        guard let command = commands[cmd] else { return false }
        switch command.type {
        case "open":
            if let app = command.app {
                _runShellAsync("open -a '\(app)'", toast: toast)
            }
        case "shell":
            if let script = command.run {
                _runShellAsync(script, toast: toast)
            }
        default:
            break // "text" handled by expandText; anything else is ignored here
        }
        return true
        #else
        return false
        #endif
    }

    #if os(macOS)
    private static func _runShellAsync(_ script: String, toast: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process(); let pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", script]
            p.standardOutput = pipe; p.standardError = pipe
            do {
                try p.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    if p.isRunning { p.terminate() }
                }
                p.waitUntilExit()
            } catch {
                DispatchQueue.main.async { toast("執行失敗: \(error.localizedDescription)") }
            }
        }
    }
    #endif
}
