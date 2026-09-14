import AppKit
import SwiftUI

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Edit menu — enables Cmd+C/V/X/A in text fields
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "關於 Yabomish 設定", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "結束 Yabomish 設定", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        mainMenu.addItem(appItem)
        mainMenu.addItem(editItem)
        // View menu — Cmd+1..5 切換頂層 tab（經 NotificationCenter 轉給 ContentView.selection）
        let viewMenu = NSMenu(title: "View")
        #if MINIMAL
        let tabTitles = ["輸入", "快捷碼", "外觀", "關於"]
        #else
        let tabTitles = ["輸入", "聯想與詞庫", "快捷碼", "外觀", "關於"]
        #endif
        for (i, title) in tabTitles.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(AppDelegate.selectTab(_:)), keyEquivalent: "\(i + 1)")
            item.tag = i
            viewMenu.addItem(item)
        }
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)
        NSApp.mainMenu = mainMenu

        createWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createWindow() {
        // isReleasedWhenClosed=false：預設 true 會在關窗時釋放 NSWindow，
        // 之後 window setter 再 release 一次 → double-free SIGSEGV
        // （dock 點擊觸發 applicationShouldHandleReopen → createWindow）
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.isReleasedWhenClosed = false
        w.title = "Yabomish 設定"
        let store = PrefsStore()
        w.contentView = NSHostingView(rootView: ContentView(store: store))
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }
    @objc func selectTab(_ sender: NSMenuItem) {
        NotificationCenter.default.post(name: .selectPrefsTab, object: sender.tag)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let w = window {
                // 視窗還活著（isReleasedWhenClosed=false）— 直接重用
                w.makeKeyAndOrderFront(nil)
            } else {
                createWindow()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}
