import Cocoa
import InputMethodKit
import NaturalLanguage



/// Hardware keyCode → QWERTY character mapping (layout-independent)
private let keyCodeToChar: [UInt16: Character] = [
    0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
    8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
    16: "y", 17: "t", 32: "u", 34: "i", 31: "o", 35: "p",
    38: "j", 40: "k", 37: "l", 45: "n", 46: "m",
    43: ",", 47: ".", 41: ";", 44: "/",
    33: "[", 30: "]",
    27: "-", 24: "=", 42: "\\", 50: "`",
]

/// Selection key keyCodes (number row: 1-9, 0)
private let keyCodeToDigit: [UInt16: Character] = [
    18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
    22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
]

/// Shift+key → QWERTY shifted symbol (layout-independent)
private let keyCodeToShifted: [UInt16: Character] = [
    18: "!", 19: "@", 20: "#", 21: "$", 23: "%",
    22: "^", 26: "&", 28: "*", 25: "(", 29: ")",
    27: "_", 24: "+", 33: "{", 30: "}", 42: "|",
    41: ":", 39: "\"", 43: "<", 47: ">", 44: "?",
    50: "~",
]

/// Standard Zhuyin keyboard: keyCode → Zhuyin symbol
private let keyCodeToZhuyin: [UInt16: String] = [
    // Number row: 1→ㄅ, 2→ㄉ, 5→ㄓ, 8→ㄚ, 9→ㄞ, 0→ㄢ, -→ㄦ
    18: "ㄅ", 19: "ㄉ", 23: "ㄓ", 28: "ㄚ", 25: "ㄞ", 29: "ㄢ", 27: "ㄦ",
    // Q row
    12: "ㄆ", 13: "ㄊ", 14: "ㄍ", 15: "ㄐ", 17: "ㄔ", 16: "ㄗ",
    32: "ㄧ", 34: "ㄛ", 31: "ㄟ", 35: "ㄣ",
    // A row
    0: "ㄇ", 1: "ㄋ", 2: "ㄎ", 3: "ㄑ", 5: "ㄕ", 4: "ㄘ",
    38: "ㄨ", 40: "ㄜ", 37: "ㄠ", 41: "ㄤ",
    // Z row
    6: "ㄈ", 7: "ㄌ", 8: "ㄏ", 9: "ㄒ", 11: "ㄖ", 45: "ㄙ",
    46: "ㄩ", 43: "ㄝ", 47: "ㄡ", 44: "ㄥ",
]

/// Tone keyCodes: 3→ˇ, 4→ˋ, 6→ˊ, 7→˙  (space = tone 1)
private let keyCodeToTone: [UInt16: String] = [
    22: "ˊ", 20: "ˇ", 21: "ˋ", 26: "˙",
]

@objc(YabomishInputController)
class YabomishInputController: IMKInputController {

    // MARK: - Shared

    static let cinTable: CINTable = {
        let t = CINTable()
        t.reload()
        if t.isEmpty { DebugLog.log("YabomishIM: No CIN table. Place liu.cin in ~/Library/YabomishIM/") }
        return t
    }()

    private static let freqTracker = FreqTracker()
    private static weak var activeSession: YabomishInputController?
    private static var lastDeactivateTime: Date = .distantPast
    private static var hasPromptedImport = false
    private static var yabomishWasActive = false

    private static let inputSourceObserver: Void = {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil, queue: .main
        ) { _ in
            let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
            let id = src.flatMap { TISGetInputSourceProperty($0, kTISPropertyInputSourceID) }
                .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
            if id?.contains("yabomishim") != true {
                yabomishWasActive = false
            }
        }
    }()

    private var panel: CandidatePanel { CandidatePanel.shared }

    // MARK: - Key Handling

    override func recognizedEvents(_ sender: Any!) -> Int {
        let flags: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
        return Int(flags.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }
        guard event.type == .keyDown || event.type == .flagsChanged else { return false }
        guard let client = sender as? (NSObjectProtocol & IMKTextInput) else { return false }
        if IsSecureEventInputEnabled() { return false }
        return handleWithNewEngine(event, client: client)
    }

    // MARK: - Mode Toast

    private static var modeWindow: NSPanel?

    private func showModeToast(_ text: String) {
        Self.modeWindow?.orderOut(nil)
        guard let screen = NSScreen.main else { return }
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: YabomishPrefs.toastFontSize, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()
        let w = max(label.frame.width + 32, 56)
        let h = label.frame.height + 20
        let rect = NSRect(x: screen.frame.midX - w/2, y: screen.frame.midY - h/2, width: w, height: h)
        let win = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        win.level = .popUpMenu
        win.isOpaque = false
        win.backgroundColor = .clear
        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: rect.size))
        bg.material = .hudWindow; bg.state = .active; bg.wantsLayer = true; bg.layer?.cornerRadius = 12
        win.contentView = bg
        label.frame = NSRect(x: 0, y: 10, width: rect.width, height: label.frame.height)
        bg.addSubview(label)
        win.orderFront(nil)
        Self.modeWindow = win
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.3; win.animator().alphaValue = 0 }) {
                win.orderOut(nil); if Self.modeWindow === win { Self.modeWindow = nil }
            }
        }
    }

    // MARK: - Code Hint Toast

    private static var codeHintWindow: NSPanel?

    private func showCodeHintToast(_ text: String, duration: Double = 1.2) {
        Self.codeHintWindow?.orderOut(nil)
        guard let screen = NSScreen.main else { return }
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()
        let w = label.frame.width + 24
        let h = label.frame.height + 12
        let rect = NSRect(x: screen.frame.midX - w/2, y: screen.frame.midY + 60, width: w, height: h)
        let win = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        win.level = .popUpMenu
        win.isOpaque = false; win.backgroundColor = .clear
        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: rect.size))
        bg.material = .hudWindow; bg.state = .active; bg.wantsLayer = true; bg.layer?.cornerRadius = 8
        win.contentView = bg
        label.frame = NSRect(x: 0, y: 4, width: rect.width, height: label.frame.height)
        bg.addSubview(label)
        win.orderFront(nil)
        Self.codeHintWindow = win
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.3; win.animator().alphaValue = 0 }) {
                win.orderOut(nil); if Self.codeHintWindow === win { Self.codeHintWindow = nil }
            }
        }
    }

    // MARK: - Candidate Panel

    private static var cachedActiveScreen: (screen: NSScreen, time: Date)?

    private func activeScreen(for client: IMKTextInput) -> NSScreen {
        if let cached = Self.cachedActiveScreen, Date().timeIntervalSince(cached.time) < 0.5 {
            return cached.screen
        }
        let result: NSScreen
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            result = screen
        } else if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            var best: (screen: NSScreen, area: CGFloat) = (NSScreen.main ?? NSScreen.screens[0], 0)
            for info in list {
                guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32, ownerPID == pid,
                      let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                      let x = bounds["X"], let y = bounds["Y"],
                      let w = bounds["Width"], let h = bounds["Height"] else { continue }
                let area = w * h
                guard area > best.area else { continue }
                if let s = NSScreen.screens.first(where: {
                    $0.frame.contains(NSPoint(x: x + w / 2, y: $0.frame.maxY - y - h / 2))
                }) { best = (s, area) }
            }
            result = best.screen
        } else {
            result = NSScreen.main ?? NSScreen.screens[0]
        }
        Self.cachedActiveScreen = (result, Date())
        return result
    }

    override func candidates(_ sender: Any!) -> [Any]! {
        engine.currentCandidates as [Any]
    }

    // MARK: - Session

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        let prefsItem = NSMenuItem(title: "偏好設定⋯", action: #selector(openPrefs), keyEquivalent: "")
        prefsItem.target = self
        menu.addItem(prefsItem)
        return menu
    }

    @objc private func openPrefs() {
        let appURL = URL(fileURLWithPath: "/Applications/YabomishPrefs.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        } else {
            PrefsWindow.shared.showWindow()
        }
    }

    private static var lastAppliedKeyboardLayout: String?

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        _ = Self.inputSourceObserver
        let targetLayout = "com.apple.keylayout.ABC"
        if let client = sender as? IMKTextInput {
            client.overrideKeyboard(withKeyboardNamed: targetLayout)
        }
        if Self.cinTable.isEmpty && !Self.hasPromptedImport {
            Self.hasPromptedImport = true
            DispatchQueue.main.async { Self.promptImportCIN() }
        }
        let fromOtherIM = !Self.yabomishWasActive
        Self.yabomishWasActive = true
        if fromOtherIM {
            DispatchQueue.global(qos: .userInitiated).async {
                _ = PhraseLookup.shared
                _ = WikiCorpus.shared
                _ = BigramSuggest.shared
            }
        }
        Self.activeSession = self
        panel.onCandidateSelected = { [weak self] text in
            guard let self else { return }
            let idx = self.engine.currentCandidates.firstIndex(of: text) ?? 0
            self.engine.selectCandidate(at: idx)
        }
        // Reset engine state for new session
        engine.handleEscape()
        engine.clearCandidates()
        if fromOtherIM && YabomishPrefs.showActivateToast {
            showModeToast(engine.currentModeLabel)
        }
        if !DataDownloader.isDataAvailable {
            DataDownloader.ensureData { ok in
                if !ok { DebugLog.log("YabomishIM: 語料尚未下載，聯想/重排功能停用") }
            }
        }
    }

    override func deactivateServer(_ sender: Any!) {
        guard Self.activeSession === self else {
            super.deactivateServer(sender)
            return
        }
        if let client = sender as? (NSObjectProtocol & IMKTextInput) {
            if engine.isZhuyinMode || engine.isPinyinMode {
                engine.handleEscape()
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            } else if !engine.composing.isEmpty {
                if !engine.currentCandidates.isEmpty {
                    engineClient = client
                    engine.handleSpace()
                } else {
                    engine.handleEscape()
                    client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                         replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                }
            }
        }
        panel.hide()
        Self.activeSession = nil
        Self.lastDeactivateTime = Date()
        super.deactivateServer(sender)
    }

    // MARK: - CIN Import

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

    static func importCIN(from url: URL, attachedTo window: NSWindow?) {
        importSelectedCIN(from: url, attachedTo: window)
    }

    static func importCIN(attachedTo window: NSWindow? = nil) {
        DispatchQueue.main.async {
            guard let src = chooseCINFileURL() else { return }
            importSelectedCIN(from: src, attachedTo: window)
        }
    }

    private static func chooseCINFileURL() -> URL? {
        var result: URL?
        let work = {
            let panel = NSOpenPanel()
            panel.prompt = "匯入"
            panel.message = "選擇嘸蝦米字表 (.cin)"
            panel.allowedContentTypes = [.plainText]
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
        let dir = NSHomeDirectory() + "/Library/YabomishIM"
        let dst = dir + "/liu.cin"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(atPath: dst)
        do {
            try FileManager.default.copyItem(at: src, to: URL(fileURLWithPath: dst))
            try? FileManager.default.removeItem(atPath: dst + ".cache")
            cinTable.reload()
            hasPromptedImport = false
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

// MARK: - New InputEngine Integration

extension YabomishInputController {

    private class WeakClientWrapper {
        weak var client: (NSObjectProtocol & IMKTextInput)?
        init(_ client: (NSObjectProtocol & IMKTextInput)?) { self.client = client }
    }

    private static var _engineClientKey = 0
    private weak var engineClient: (NSObjectProtocol & IMKTextInput)? {
        get { (objc_getAssociatedObject(self, &Self._engineClientKey) as? WeakClientWrapper)?.client }
        set { objc_setAssociatedObject(self, &Self._engineClientKey, WeakClientWrapper(newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private static var _engineKey = 0
    var engine: InputEngine {
        if let e = objc_getAssociatedObject(self, &Self._engineKey) as? InputEngine { return e }
        let e = InputEngine()
        e.delegate = self
        e.loadTable()
        objc_setAssociatedObject(self, &Self._engineKey, e, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return e
    }

    func handleWithNewEngine(_ event: NSEvent, client: NSObjectProtocol & IMKTextInput) -> Bool {
        engineClient = client

        if event.type == .flagsChanged {
            return handleNewEngineFlagsChanged(event)
        }

        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return false
        }

        // English mode
        if engine.isEnglishMode {
            if flags.contains(.shift) { newEngineShiftUsed = true }
            let wantShift = flags.contains(.shift) != flags.contains(.capsLock)
            if wantShift, let sh = keyCodeToShifted[keyCode] {
                client.insertText(String(sh), replacementRange: notFoundRange)
                return true
            }
            if let ch = keyCodeToChar[keyCode] ?? keyCodeToDigit[keyCode] {
                var s = String(ch)
                if wantShift { s = s.uppercased() }
                client.insertText(s, replacementRange: notFoundRange)
                return true
            }
            return false
        }

        // Shift held: temporary English / wildcard / full-width space
        if flags.contains(.shift) && !flags.contains(.command) && !flags.contains(.control) && !flags.contains(.option) {
            newEngineShiftUsed = true
            // Shift+digit while candidates showing → output digit directly
            if let digit = keyCodeToDigit[keyCode], !engine.currentCandidates.isEmpty {
                if !engine.composing.isEmpty {
                    if !engine.currentCandidates.isEmpty { engine.handleSpace() }
                    else { engine.handleEscape() }
                } else {
                    engine.clearCandidates()
                    panel.hide()
                }
                client.insertText(String(digit), replacementRange: notFoundRange)
                return true
            }
            if keyCode == 28 && !engine.composing.isEmpty {
                engine.handleWildcard()
                return true
            }
            if keyCode == 49 {
                if !engine.composing.isEmpty {
                    if !engine.currentCandidates.isEmpty { engine.handleSpace() }
                    else { engine.handleEscape() }
                }
                client.insertText("\u{3000}", replacementRange: notFoundRange)
                return true
            }
            if !engine.composing.isEmpty {
                if !engine.currentCandidates.isEmpty { engine.handleSpace() }
                else { engine.handleEscape() }
            }
            if let ch = keyCodeToChar[keyCode] {
                let s = flags.contains(.capsLock) ? String(ch).uppercased() : String(ch)
                client.insertText(s, replacementRange: notFoundRange)
                return true
            }
            if let sh = keyCodeToShifted[keyCode] {
                client.insertText(String(sh), replacementRange: notFoundRange)
                return true
            }
            return false
        }

        // Zhuyin mode
        if engine.isZhuyinMode {
            return handleNewEngineZhuyin(keyCode, client: client)
        }

        // Pinyin mode
        if engine.isPinyinMode {
            return handleNewEnginePinyin(keyCode, client: client)
        }

        // Special keys
        switch keyCode {
        case 49: // Space
            if engine.composing.isEmpty { return false }
            engine.handleSpace()
            return true
        case 51: // Backspace
            if engine.composing.isEmpty { return false }
            engine.handleBackspace()
            return true
        case 53: // Escape
            if engine.composing.isEmpty {
                if !engine.currentCandidates.isEmpty {
                    engine.clearCandidates()
                    panel.hide()
                    return true
                }
                return false
            }
            engine.handleEscape()
            return true
        case 36: // Enter
            if engine.composing.isEmpty { return false }
            engine.handleEnter()
            return true
        case 39: // Quote
            engine.handleQuote()
            return true
        default: break
        }

        // Arrow keys
        if panel.isVisible_ && (keyCode >= 123 && keyCode <= 126) {
            if engine.composing.isEmpty {
                engine.clearCandidates()
                panel.hide()
                return false
            }
            if panel.isFixedMode {
                switch keyCode {
                case 123: panel.movePrev(); return true
                case 124: panel.moveNext(); return true
                case 126: panel.pageUp(); return true
                case 125: panel.pageDown(); return true
                default: break
                }
            } else {
                switch keyCode {
                case 126: panel.moveUp(); return true
                case 125: panel.moveDown(); return true
                case 123: panel.pageUp(); return true
                case 124: panel.pageDown(); return true
                default: break
                }
            }
        }

        // Tab, PageDown, PageUp
        if keyCode == 48 && panel.isVisible_ { panel.pageDown(); return true }
        if keyCode == 121 && panel.isVisible_ { panel.pageDown(); return true }
        if keyCode == 116 && panel.isVisible_ { panel.pageUp(); return true }

        // VRSF quick-select
        if let ch = keyCodeToChar[keyCode], engine.handleVRSF(String(ch)) {
            return true
        }

        // Digit keys — select candidate (composing or suggestion mode)
        if !engine.currentCandidates.isEmpty, let digit = keyCodeToDigit[keyCode] {
            if let selected = panel.selectByKey(digit) {
                let idx = engine.currentCandidates.firstIndex(of: selected) ?? 0
                engine.selectCandidate(at: idx)
                return true
            }
        }

        // Non-CIN punctuation passthrough: - = \ `  ([ ] are used by CIN)
        let passthroughKeyCodes: Set<UInt16> = [27, 24, 42, 50]  // - = \ `
        if passthroughKeyCodes.contains(keyCode) {
            if !engine.composing.isEmpty {
                if !engine.currentCandidates.isEmpty { engine.handleSpace() }
                else { engine.handleEscape() }
            }
            if let sh = keyCodeToShifted[keyCode], flags.contains(.shift) {
                client.insertText(String(sh), replacementRange: notFoundRange)
            } else if let ch = keyCodeToChar[keyCode] {
                client.insertText(String(ch), replacementRange: notFoundRange)
            }
            return true
        }

        // '/' passthrough when idle
        if keyCode == 44 && engine.composing.isEmpty {
            client.insertText("/", replacementRange: notFoundRange)
            return true
        }

        // Letter/punctuation keys
        if let ch = keyCodeToChar[keyCode] {
            engine.handleLetter(String(ch))
            return true
        }

        // Digits when idle (no composing AND no candidates)
        if engine.composing.isEmpty && engine.currentCandidates.isEmpty, let digit = keyCodeToDigit[keyCode] {
            client.insertText(String(digit), replacementRange: notFoundRange)
            return true
        }

        return !engine.composing.isEmpty
    }

    // MARK: - New Engine Helpers

    private var notFoundRange: NSRange {
        NSRange(location: NSNotFound, length: NSNotFound)
    }

    private static var _shiftDownKey = 0
    private var newEngineLastShiftDown: TimeInterval {
        get { (objc_getAssociatedObject(self, &Self._shiftDownKey) as? NSNumber)?.doubleValue ?? 0 }
        set { objc_setAssociatedObject(self, &Self._shiftDownKey, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private static var _shiftUsedKey = 0
    private var newEngineShiftUsed: Bool {
        get { (objc_getAssociatedObject(self, &Self._shiftUsedKey) as? NSNumber)?.boolValue ?? false }
        set { objc_setAssociatedObject(self, &Self._shiftUsedKey, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private func handleNewEngineFlagsChanged(_ event: NSEvent) -> Bool {
        let shiftDown = event.modifierFlags.contains(.shift)
        if shiftDown {
            newEngineLastShiftDown = event.timestamp
            newEngineShiftUsed = false
        } else if newEngineLastShiftDown > 0 {
            if event.timestamp - newEngineLastShiftDown < 0.3 && !newEngineShiftUsed {
                engine.toggleEnglishMode()
            }
            newEngineLastShiftDown = 0
        }
        return false
    }

    private func handleNewEngineZhuyin(_ keyCode: UInt16, client: NSObjectProtocol & IMKTextInput) -> Bool {
        if keyCode == 53 { // Escape
            if !engine.currentCandidates.isEmpty || !engine.composing.isEmpty {
                engine.handleEscape()
            } else {
                engine.exitZhuyinMode()
            }
            return true
        }
        if keyCode == 51 { engine.handleBackspace(); return true }

        // Candidates showing: selection/navigation
        if !engine.currentCandidates.isEmpty {
            if let digit = keyCodeToDigit[keyCode], let selected = panel.selectByKey(digit) {
                let idx = engine.currentCandidates.firstIndex(of: selected) ?? 0
                engine.selectCandidate(at: idx)
                return true
            }
            if keyCode == 49 { panel.pageDown(); return true }
            if panel.isFixedMode {
                if keyCode == 123 { panel.movePrev(); return true }
                if keyCode == 124 { panel.moveNext(); return true }
                if keyCode == 126 { panel.pageUp(); return true }
                if keyCode == 125 { panel.pageDown(); return true }
            } else {
                if keyCode == 126 { panel.moveUp(); return true }
                if keyCode == 125 { panel.moveDown(); return true }
                if keyCode == 123 { panel.pageUp(); return true }
                if keyCode == 124 { panel.pageDown(); return true }
            }
            if keyCode == 48 { panel.pageDown(); return true }
            if keyCode == 36, let sel = panel.selectedCandidate() {
                let idx = engine.currentCandidates.firstIndex(of: sel) ?? 0
                engine.selectCandidate(at: idx)
                return true
            }
            return true
        }

        // Tone keys
        if let tone = keyCodeToTone[keyCode] {
            engine.handleZhuyinTone(tone)
            return true
        }
        if keyCode == 49 { engine.handleZhuyinSpace(); return true }

        // Zhuyin symbol
        if let zy = keyCodeToZhuyin[keyCode] {
            engine.handleZhuyinSymbol(zy)
            return true
        }

        return true
    }

    private func handleNewEnginePinyin(_ keyCode: UInt16, client: NSObjectProtocol & IMKTextInput) -> Bool {
        if keyCode == 53 { engine.handlePinyinEscape(); return true }
        if keyCode == 51 { engine.handlePinyinBackspace(); return true }

        // Candidates showing: selection/navigation
        if !engine.currentCandidates.isEmpty {
            if let digit = keyCodeToDigit[keyCode], let selected = panel.selectByKey(digit) {
                let idx = engine.currentCandidates.firstIndex(of: selected) ?? 0
                engine.selectPinyinCandidate(at: idx)
                return true
            }
            if keyCode == 49 { panel.pageDown(); return true }
            if panel.isFixedMode {
                if keyCode == 123 { panel.movePrev(); return true }
                if keyCode == 124 { panel.moveNext(); return true }
                if keyCode == 126 { panel.pageUp(); return true }
                if keyCode == 125 { panel.pageDown(); return true }
            } else {
                if keyCode == 126 { panel.moveUp(); return true }
                if keyCode == 125 { panel.moveDown(); return true }
                if keyCode == 123 { panel.pageUp(); return true }
                if keyCode == 124 { panel.pageDown(); return true }
            }
            if keyCode == 48 { panel.pageDown(); return true }
            if keyCode == 36, let sel = panel.selectedCandidate() {
                let idx = engine.currentCandidates.firstIndex(of: sel) ?? 0
                engine.selectPinyinCandidate(at: idx)
                return true
            }
            return true
        }

        // Digit 1-5 = tone
        if let digit = keyCodeToDigit[keyCode], let d = digit.wholeNumberValue, (1...5).contains(d) {
            engine.handlePinyinTone(d)
            return true
        }
        if keyCode == 49 { engine.handlePinyinSpace(); return true }

        // Letter keys
        if let ch = keyCodeToChar[keyCode], ch.isLetter {
            engine.handlePinyinLetter(String(ch))
            return true
        }

        return true
    }
}

// MARK: - InputEngineDelegate

extension YabomishInputController: InputEngineDelegate {

    func engineDidUpdateComposing(_ text: String) {
        guard let client = engineClient else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.textColor
        ]
        let marked = NSAttributedString(string: text, attributes: attrs)
        client.setMarkedText(marked, selectionRange: NSRange(location: text.count, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    func engineDidUpdateCandidates(_ candidates: [String]) {
        guard let client = engineClient else { return }
        if candidates.isEmpty {
            panel.hide()
        } else {
            showNewEngineCandidatePanel(client: client)
        }
    }

    func engineDidCommit(_ text: String) {
        guard let client = engineClient else { return }
        let range = client.markedRange()
        let output = text.replacingOccurrences(of: "\\n", with: "\n")
        if output.count > range.length && range.length > 0 {
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                 replacementRange: range)
            client.insertText(output, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        } else {
            client.insertText(output, replacementRange: range)
        }
    }

    func engineDidCommitPair(_ left: String, _ right: String) {
        guard let client = engineClient else { return }
        let range = client.markedRange()
        client.insertText(left + right, replacementRange: range)
        let sel = client.selectedRange()
        if sel.location != NSNotFound && sel.location > 0 {
            client.setMarkedText("", selectionRange: NSRange(location: sel.location - right.count, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }
    }

    func engineDidClearComposing() {
        guard let client = engineClient else { return }
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        panel.hide()
    }

    func engineDidShowToast(_ text: String) {
        showModeToast(text)
    }

    func engineDidDeleteBack() {
        guard let client = engineClient else { return }
        let sel = client.selectedRange()
        if sel.location != NSNotFound && sel.location > 0 {
            client.insertText("", replacementRange: NSRange(location: sel.location - 1, length: 1))
        }
    }

    func engineDidSuggest(_ suggestions: [String]) {
        guard let client = engineClient else { return }
        if engine.composing.isEmpty && !suggestions.isEmpty {
            engine.setCandidates(suggestions)
            showNewEngineCandidatePanel(client: client)
        }
    }

    private func showNewEngineCandidatePanel(client: NSObjectProtocol & IMKTextInput) {
        let candidates = engine.currentCandidates
        guard !candidates.isEmpty else { panel.hide(); return }

        var cursorRect = NSRect.zero
        let markedRange = client.markedRange()
        let queryRange: NSRange
        if markedRange.location != NSNotFound && markedRange.length > 0 {
            queryRange = NSRange(location: NSMaxRange(markedRange), length: 0)
        } else {
            queryRange = client.selectedRange()
        }
        if queryRange.location != NSNotFound {
            var loc = queryRange.location
            cursorRect = client.firstRect(forCharacterRange: queryRange, actualRange: nil)
            while cursorRect.origin == .zero && loc > 0 {
                loc -= 1
                cursorRect = client.firstRect(
                    forCharacterRange: NSRange(location: loc, length: 0), actualRange: nil)
            }
        }

        let hasCursor: Bool = {
            guard cursorRect.minX > 0 || cursorRect.minY > 0
                  || cursorRect.size.height > 0 else { return false }
            let pt = NSPoint(x: cursorRect.midX, y: cursorRect.midY)
            return NSScreen.screens.contains(where: { $0.visibleFrame.contains(pt) })
        }()
        if hasCursor {
            let pt = NSPoint(x: cursorRect.midX, y: cursorRect.midY)
            panel.targetScreen = NSScreen.screens.first(where: { $0.frame.contains(pt) })
        }

        let origin: NSPoint
        if YabomishPrefs.panelPosition == "fixed" {
            panel.fallbackFixed = false; origin = .zero
        } else if hasCursor {
            panel.fallbackFixed = false; origin = NSPoint(x: cursorRect.minX, y: cursorRect.minY)
        } else {
            panel.fallbackFixed = true; origin = .zero
        }

        panel.modeTag = engine.currentModeLabel
        panel.show(candidates: candidates, selKeys: engine.selKeys, at: origin, composing: engine.composing)
    }
}
