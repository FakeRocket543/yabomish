import AppKit
import SwiftUI

// Single instance check
let dominated = NSRunningApplication.runningApplications(withBundleIdentifier: "com.yabomish.prefs")
if dominated.count > 1 {
    dominated.first { $0 != .current }?.activate()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Yabomish 偏好設定"
        let store = PrefsStore()
        window.contentView = NSHostingView(rootView: ContentView(store: store))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
