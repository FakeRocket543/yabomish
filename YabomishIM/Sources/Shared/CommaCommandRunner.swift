import Foundation

/// 外部指令 commands.json — v2 schema（三平台共用契約）
///
/// ```json
/// {
///   "auau": { "type": "text",  "text": "sudo apt update && sudo apt upgrade" },
///   "ss":   { "type": "shell", "run": "~/.../yabomish_capture.sh screen" },
///   "saf":  { "type": "open",  "app": "Safari" },
///   "ask":  { "type": "hermes", "send": "幫我總結這篇" }
/// }
/// ```
///
/// - `text`   → 展開成文字直接送出（macOS/iOS/Android 三平台）
/// - `shell`  → 執行 shell 指令（僅 macOS）
/// - `open`   → 開啟 app（僅 macOS）
/// - `hermes` → POST 明確觸發的字串到本機 Hermes agent，回覆插入游標處（僅 macOS）
enum CommaCommandRunner {

    struct Command: Decodable {
        let type: String
        let app: String?
        let run: String?
        let text: String?
        let send: String?
        let url: String?
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

    /// Try to execute a platform command (shell/open/hermes, macOS-only).
    /// Returns true if matched. `deliver` receives text to insert at the cursor
    /// (hermes replies) on the main queue.
    static func tryExecute(_ cmd: String,
                           toast: @escaping (String) -> Void,
                           deliver: @escaping (String) -> Void = { _ in }) -> Bool {
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
        case "hermes":
            if let payload = command.send {
                _askHermes(payload: payload, url: command.url, toast: toast, deliver: deliver)
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
    /// Localhost-only Hermes bridge. Sends ONLY the explicitly configured
    /// `send` string — never keystrokes or context — to a local agent listener;
    /// the reply is delivered to the cursor. This is the same trust shape as
    /// ,,v clipboard processing: user-triggered, single payload, no background
    /// telemetry of any kind.
    private static func _askHermes(payload: String, url: String?,
                                   toast: @escaping (String) -> Void,
                                   deliver: @escaping (String) -> Void) {
        guard let endpoint = Self.hermesEndpoint(url) else {
            toast("Hermes 僅允許本機位址（127.0.0.1 / localhost / ::1）"); return
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": payload])
        toast("Hermes …")
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    toast("Hermes 失敗: \(error.localizedDescription)")
                    return
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let data, let body = String(data: data, encoding: .utf8),
                      !body.isEmpty else {
                    toast("Hermes 無回應"); return
                }
                deliver(Self._hermesReplyText(body))
            }
        }.resume()
    }
    /// Hermes endpoints are loopback-only. commands.json is a sync-sourced
    /// file; without this gate a tampered entry could exfiltrate the payload
    /// (or probe) to an arbitrary host. Host must be 127.0.0.1, localhost,
    /// or ::1 — no DNS names, no LAN IPs, no schemes other than http.
    static func hermesEndpoint(_ url: String?) -> URL? {
        guard let endpoint = URL(string: url ?? "http://127.0.0.1:8765/ask"),
              endpoint.scheme == "http",
              let host = endpoint.host?.lowercased()
        else { return nil }
        guard host == "127.0.0.1" || host == "localhost" || host == "[::1]" || host == "::1" else {
            return nil
        }
        return endpoint
    }

    /// Accept plain text or `{"text"|"reply"|"response": "..."}` JSON bodies.
    static func _hermesReplyText(_ body: String) -> String {
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["text", "reply", "response", "content"] {
                if let s = obj[key] as? String, !s.isEmpty { return s }
            }
        }
        return body
    }

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
