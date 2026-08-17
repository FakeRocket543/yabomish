import AppKit

/// CIN table import flow: prompt, file picker, copy, reload, result alerts.
/// Extracted from YabomishInputController (god-class surgery, zero behavior change).
enum CINImportCoordinator {
    static var hasPromptedImport = false
    static var showFirstUseTip = false

    static let cinTable = YabomishInputController.cinTable

    static func promptImportCIN() {
        activateForForegroundUI()
        let alert = NSAlert()
        alert.messageText = "尚未偵測到字表"
        alert.informativeText = "Yabomish 需要嘸蝦米字表（liu.cin）才能輸入中文。\n請點「匯入」選擇你的 liu.cin 檔案。"
        alert.addButton(withTitle: "匯入⋯")
        alert.addButton(withTitle: "稍後")
        alert.alertStyle = .warning
        alert.window.level = .modalPanel
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        importCIN()
    }

    static func reloadTable() {
        cinTable.reload()
        DebugLog.log("YabomishIM: table reloaded via UI, maxCodeLength=\(cinTable.maxCodeLength)")
    }

    static func importCIN(attachedTo window: NSWindow? = nil) {
        DispatchQueue.main.async {
            guard let src = chooseCINFileURL() else { return }
            importSelectedCIN(from: src, attachedTo: window)
        }
    }

    static func importCIN(from url: URL, attachedTo window: NSWindow?) {
        importSelectedCIN(from: url, attachedTo: window)
    }

    private static func chooseCINFileURL() -> URL? {
        var result: URL?
        let work = {
            let panel = NSOpenPanel()
            panel.prompt = "匯入"
            panel.message = "選擇嘸蝦米字表 (.cin)"
            // FIX: .cin is not a system-recognized UTType — using .plainText alone
            // causes .cin files to appear grayed-out. Use [.plainText, .data] to allow selection.
            panel.allowedContentTypes = [.plainText, .data]
            panel.allowsOtherFileTypes = true
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.level = .floating
            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK {
                result = panel.url
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync { work() }
        }
        return result
    }

    private static func activateForForegroundUI() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func importSelectedCIN(from src: URL, attachedTo window: NSWindow?) {
        let dir = AppConstants.sharedDir
        let dst = dir + "/liu.cin"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(atPath: dst)
        do {
            try FileManager.default.copyItem(at: src, to: URL(fileURLWithPath: dst))
            try? FileManager.default.removeItem(atPath: dst + ".cache")
            cinTable.reload()
            // Pre-build lazy caches now to avoid lag on first keystroke
            DispatchQueue.global(qos: .userInitiated).async {
                _ = cinTable.shortestCodesTable
                _ = cinTable.longestCodesTable
                DebugLog.log("YabomishIM: Pre-built code tables after import")
            }
            hasPromptedImport = false
            showFirstUseTip = true
            DebugLog.log("YabomishIM: Imported CIN table from \(src.path)")
            showImportAlert(
                messageText: "字表匯入成功",
                informativeText: "已匯入 \(cinTable.isEmpty ? 0 : cinTable.shortestCodesTable.count) 字。",
                style: .informational,
                attachedTo: window
            )
        } catch {
            showImportAlert(
                messageText: "匯入失敗",
                informativeText: error.localizedDescription,
                style: .critical,
                attachedTo: window
            )
        }
    }

    private static func showImportAlert(messageText: String,
                                        informativeText: String,
                                        style: NSAlert.Style,
                                        attachedTo window: NSWindow?) {
        activateForForegroundUI()
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = style
        if let window {
            window.makeKeyAndOrderFront(nil)
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
