// live e2e 受測 app:NSWindow + NSTextField,把每次文字變更 append 到
// /tmp/e2e_live_out.txt。行為斷言由外部 driver 讀檔判定。
import Cocoa

let logPath = "/tmp/e2e_live_out.txt"
FileManager.default.createFile(atPath: logPath, contents: nil)

func log(_ s: String) {
    let line = String(format: "%.3f %@\n", ProcessInfo.processInfo.systemUptime, s)
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
    }
}

final class App: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    let win = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 480, height: 120),
                       styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let field = NSTextField(frame: NSRect(x: 20, y: 40, width: 440, height: 40))

    func applicationDidFinishLaunching(_ n: Notification) {
        field.font = .systemFont(ofSize: 20)
        field.delegate = self
        win.contentView!.addSubview(field)
        win.title = "YabomishE2E"
        win.initialFirstResponder = field
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(field)
        NSApp.activate(ignoringOtherApps: true)
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { ev in
            log("EV type=\(ev.type == .keyDown ? "key" : "flag") code=\(ev.keyCode) flags=\(ev.modifierFlags.rawValue)")
            return ev
        }
        log("READY")
    }

    func applicationDidBecomeActive(_ n: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            win.makeFirstResponder(field)
            log("ACTIVE key=\(win.isKeyWindow) resp=\(win.firstResponder === field)")
        }
    }

    func windowDidBecomeKey(_ n: Notification) {
        win.makeFirstResponder(field)
    }

    func controlTextDidChange(_ n: Notification) {
        let editor = field.currentEditor() as? NSTextView
        let hasMarked = editor != nil && editor!.markedRange().location != NSNotFound
        log("TEXT[\(field.stringValue)] marked=\(hasMarked)")
    }
}

let app = NSApplication.shared
let del = App()
app.setActivationPolicy(.regular)
app.delegate = del
app.run()
