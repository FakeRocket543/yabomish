import Foundation
#if os(macOS)
import AppKit

/// ,,B / ,,F — app 切換歷史的瀏覽器式前進後退。
///
/// Cmd+Tab 點按只是兩 app 間切換（恆回最近一個），無法表達「往前/往後」；
/// 這裡用 NSWorkspace 啟動通知自建 MRU 歷史 + 游標，activate() 是公開 API——
/// 不需輔助使用權限、不合成事件，語意反而比切換器強（可連退多層再 forward 回來）。
///
/// 語意比照瀏覽器：手動切到別的 app 時截斷游標後方的 forward 歷史再 push；
/// 自家 activate 產生的通知因 history[cursor] 已是目標 pid 而被吸收。
/// 只追 .regular app（略過選單列代理與 daemon），死掉的 pid 在導航時順手清。
final class AppSwitchTracker {
    static let shared = AppSwitchTracker()

    private var history: [pid_t] = []
    private var cursor = 0
    private static let maxDepth = 30

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(_appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        if let front = NSWorkspace.shared.frontmostApplication {
            history = [front.processIdentifier]
        }
    }

    /// 啟動追蹤（進程啟動時呼叫一次，越早歷史越完整）
    static func warmUp() { _ = shared }

    @objc private func _appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular else { return }
        let pid = app.processIdentifier
        DispatchQueue.main.async { self._record(pid) }
    }

    private func _record(_ pid: pid_t) {
        if cursor < history.count, history[cursor] == pid { return } // 自家 activate 或同 app 重複
        if cursor < history.count - 1 { history.removeSubrange((cursor + 1)...) } // 截斷 forward
        history.append(pid)
        cursor = history.count - 1
        if history.count > Self.maxDepth { history.removeFirst(); cursor -= 1 }
    }

    /// ,,B：切到歷史中較早的 app。回傳目標 app 名，nil = 無更早記錄。
    func back() -> String? { _move(-1) }
    /// ,,F：切回較新的 app。回傳目標 app 名，nil = 已到最新。
    func forward() -> String? { _move(+1) }

    private func _move(_ delta: Int) -> String? {
        assert(Thread.isMainThread)
        while true {
            let target = cursor + delta
            guard target >= 0, target < history.count else { return nil }
            let pid = history[target]
            if let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
                cursor = target
                app.activate(options: .activateAllWindows)
                return app.localizedName ?? "pid \(pid)"
            }
            // 死掉的 entry 拔掉；游標若在目標之後要同步下修，方向由 cursor+delta 重算
            history.remove(at: target)
            if target < cursor { cursor -= 1 }
        }
    }
}
#endif
