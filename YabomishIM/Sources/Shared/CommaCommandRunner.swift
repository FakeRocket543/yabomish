import Foundation

enum CommaCommandRunner {

    struct Command: Decodable {
        let type: String
        let app: String?
        let run: String?
    }

    private(set) static var commands: [String: Command] = [:]

    static var configPath: String {
        AppConstants.sharedDir + "/commands.json"
    }

    static func reload() {
        guard let data = FileManager.default.contents(atPath: configPath),
              let dict = try? JSONDecoder().decode([String: Command].self, from: data)
        else { commands = [:]; return }
        commands = dict
    }

    /// Try to execute an external command. Returns true if matched.
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
            toast("未知指令類型: \(command.type)")
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
