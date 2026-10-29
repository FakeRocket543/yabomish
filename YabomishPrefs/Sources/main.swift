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
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        mainMenu.addItem(editItem)
        // View menu — Cmd+數字 切換側邊欄頁（經 NotificationCenter 轉給 ContentView.selection）
        let viewMenu = NSMenu(title: "View")
        #if MINIMAL
        let tabTitles = ["輸入", "切換", "英數", "快捷碼", "候選窗", "模式提示", "介面", "說明", "關於"]
        #else
        let tabTitles = ["輸入", "切換", "英數", "聯想", "一般詞庫", "專業詞庫", "快捷碼", "候選窗", "模式提示", "介面", "說明", "關於"]
        #endif
        for (i, title) in tabTitles.enumerated() {
            // Cmd+1..9、Cmd+0 對應前 10 頁；第 11、12 頁無快捷鍵
            let key = i < 9 ? "\(i + 1)" : (i == 9 ? "0" : "")
            let item = NSMenuItem(title: title, action: #selector(AppDelegate.selectTab(_:)), keyEquivalent: key)
            item.tag = i
            viewMenu.addItem(item)
        }
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)
        NSApp.mainMenu = mainMenu

        createWindow()
        NSApp.activate(ignoringOtherApps: true)

        // 測試掛鉤：`-page N` 啟動後直接跳第 N 頁（視覺驗收/截圖用）
        let page = UserDefaults.standard.integer(forKey: "page")
        if page > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: .selectPrefsTab, object: page)
            }
        }
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
        applyAppearance(mode: store.appearanceMode, to: w)
        // AppKit 層對齊：preferredColorScheme 之外，NSColor 橋接色也要跟著模式。
        // 自動 → nil（跟隨系統）；淺色/深色 → 固定 appearance，切換瞬間不會半淺半深。
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.yabomish.prefsChanged"), object: nil, queue: .main
        ) { [weak w] _ in
            guard let w else { return }
            self.applyAppearance(mode: store.appearanceMode, to: w)
        }
        w.center()
        w.makeKeyAndOrderFront(nil)
        // 設定程式的側邊欄是主導覽，不該被收起——整條 toolbar 移除：
        // isVisible=false 只藏按鈕、材質還在會蓋住頁首內容；設 nil 才真的消失。
        // toolbar 由 NavigationSplitView 延遲建立，首輪 layout 後再拔一次。
        w.toolbar = nil
        DispatchQueue.main.async { w.toolbar = nil }
        window = w
    }
    private func applyAppearance(mode: String, to w: NSWindow) {
        switch mode {
        case "light": w.appearance = NSAppearance(named: .aqua)
        case "dark":  w.appearance = NSAppearance(named: .darkAqua)
        default:      w.appearance = nil
        }
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
