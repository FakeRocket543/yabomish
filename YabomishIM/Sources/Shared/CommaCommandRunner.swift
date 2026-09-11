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
    /// Returns true only when something was actually dispatched — 殘缺項目
    /// （open 無 app、shell 無 run、hermes 無 send、未知型別）回傳 false，
    /// 讓呼叫端的「未知命令」fallback 接手。
    static func tryExecute(_ cmd: String,
                           toast: @escaping (String) -> Void,
                           deliver: @escaping (String) -> Void = { _ in }) -> Bool {
        #if os(macOS)
        guard let command = commands[cmd] else { return false }
        switch command.type {
        case "open":
            guard let app = command.app else { return false }
            // Process+argv，不經 shell：commands.json 為同步來源，app 名含引號
            // 曾可逃出單引號執行任意指令（cf. InputEngine `,,P` 的寫法）。
            _runProcessAsync(executable: "/usr/bin/open", args: ["-a", app], toast: toast)
        case "shell":
            guard let script = command.run else { return false }
            _runShellAsync(script, toast: toast)
        case "hermes":
            guard let payload = command.send else { return false }
            _askHermes(payload: payload, url: command.url, toast: toast, deliver: deliver)
        default:
            return false // "text" 由 expandText 處理；未知型別交回未知命令 fallback
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

    /// 共用執行核心（Process+argv，無 shell）。watchdog：5 秒後 SIGTERM，
    /// 再 1 秒仍未退出則 SIGKILL 升級；stdout/stderr 導向 /dev/null——
    /// 未讀取的 pipe 會讓寫超過 64KB 的子程序卡死，waitUntilExit 永不返回。
    private static func _runProcessAsync(executable: String,
                                         args: [String],
                                         toast: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do {
                try p.run()
            } catch {
                DispatchQueue.main.async { toast("執行失敗: \(error.localizedDescription)") }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                guard p.isRunning else { return }
                p.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if p.isRunning { kill(p.processIdentifier, SIGKILL) }
                }
            }
            p.waitUntilExit() // 有 SIGKILL 升級把關，最長約 6 秒必返回
        }
    }

    private static func _runShellAsync(_ script: String, toast: @escaping (String) -> Void) {
        _runProcessAsync(executable: "/bin/zsh", args: ["-c", script], toast: toast)
    }
    #endif
}
