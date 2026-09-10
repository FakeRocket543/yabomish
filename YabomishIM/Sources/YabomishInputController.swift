import Cocoa
import InputMethodKit



/// Hardware keyCode → QWERTY character mapping (layout-independent)
private let keyCodeToChar: [UInt16: Character] = [
    0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
    8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
    16: "y", 17: "t", 32: "u", 34: "i", 31: "o", 35: "p",
    38: "j", 40: "k", 37: "l", 45: "n", 46: "m",
    43: ",", 47: ".", 41: ";", 44: "/", 39: "'",
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
        if t.isEmpty { DebugLog.log("YabomishIM: No CIN table. Place liu.cin in \(AppConstants.sharedDir)") }
        return t
    }()

    private static let freqTracker = FreqTracker()
    private static weak var activeSession: YabomishInputController?
    private static var yabomishWasActive = false

    /// App 啟動後的一次性背景任務：字頻同步資料夾合併（syncFolder ↔ freq.db）。
    /// 於背景執行緒觸發，避免 FreqTracker 首次建立時的 SQLite／JSON I/O 落在主執行緒。
    static func startBackgroundTasks() {
        DispatchQueue.global(qos: .utility).async { freqTracker.deferredMerge() }
    }

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
        if IsSecureEventInputEnabled() {
            if !engine.composing.isEmpty { engine.handleEscape() }
            panel.hide()
            return false
        }
        return handleWithNewEngine(event, client: client)
    }

    // MARK: - HUD Toast（模式切換／查碼提示共用流程）

    private static var modeWindow: NSPanel?
    private static var codeHintWindow: NSPanel?

    /// 提示視窗的靜態槽位：兩種提示各自獨立，互不覆蓋。
    private enum ToastSlot {
        case mode
        case codeHint
    }

    /// 垂直位置：模式提示置中；查碼提示固定在中線上方 60pt。
    private enum ToastVertical {
        case centered
        case fixedOffset(CGFloat)
    }

    /// 兩種提示僅以下外觀參數不同（對應原 showModeToast / showCodeHintToast）。
    private struct ToastStyle {
        let font: NSFont
        let horizontalPadding: CGFloat
        let minWidth: CGFloat          // 查碼提示無最小寬，填 0
        let verticalPadding: CGFloat
        let vertical: ToastVertical
        let cornerRadius: CGFloat
        let labelYOffset: CGFloat
    }

    private static func toastPanel(for slot: ToastSlot) -> NSPanel? {
        switch slot {
        case .mode: return modeWindow
        case .codeHint: return codeHintWindow
        }
    }

    private static func storeToastPanel(_ win: NSPanel?, for slot: ToastSlot) {
        switch slot {
        case .mode: modeWindow = win
        case .codeHint: codeHintWindow = win
        }
    }

    /// 建立並顯示 HUD 提示：先收起同槽位舊窗，淡出後僅在仍是同窗時清空槽位。
    private func showToast(_ text: String, style: ToastStyle, duration: Double, slot: ToastSlot) {
        Self.toastPanel(for: slot)?.orderOut(nil)
        guard let screen = NSScreen.main else { return }
        let label = NSTextField(labelWithString: text)
        label.font = style.font
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()
        let w = max(label.frame.width + style.horizontalPadding, style.minWidth)
        let h = label.frame.height + style.verticalPadding
        let y: CGFloat
        switch style.vertical {
        case .centered: y = screen.frame.midY - h/2
        case .fixedOffset(let offset): y = screen.frame.midY + offset
        }
        let rect = NSRect(x: screen.frame.midX - w/2, y: y, width: w, height: h)
        let win = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        win.level = .popUpMenu
        win.isOpaque = false
        win.backgroundColor = .clear
        win.appearance = YabomishPrefs.resolvedAppearance
        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: rect.size))
        bg.material = .hudWindow; bg.state = .active; bg.wantsLayer = true; bg.layer?.cornerRadius = style.cornerRadius
        win.contentView = bg
        label.frame = NSRect(x: 0, y: style.labelYOffset, width: rect.width, height: label.frame.height)
        bg.addSubview(label)
        win.orderFront(nil)
        Self.storeToastPanel(win, for: slot)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.3; win.animator().alphaValue = 0 }) {
                win.orderOut(nil); if Self.toastPanel(for: slot) === win { Self.storeToastPanel(nil, for: slot) }
            }
        }
    }

    private func showModeToast(_ text: String) {
        showToast(text, style: ToastStyle(
            font: .systemFont(ofSize: YabomishPrefs.toastFontSize, weight: .medium),
            horizontalPadding: 32, minWidth: 56, verticalPadding: 20,
            vertical: .centered, cornerRadius: 12, labelYOffset: 10
        ), duration: 0.6, slot: .mode)
    }

    private func showCodeHintToast(_ text: String, duration: Double = 1.2) {
        showToast(text, style: ToastStyle(
            font: .systemFont(ofSize: 14, weight: .regular),
            horizontalPadding: 24, minWidth: 0, verticalPadding: 12,
            vertical: .fixedOffset(60), cornerRadius: 8, labelYOffset: 4
        ), duration: duration, slot: .codeHint)
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
        let appPath = "/Applications/YabomishPrefs.app"
        guard FileManager.default.fileExists(atPath: appPath) else {
            let a = NSAlert()
            a.messageText = "找不到設定程式"
            a.informativeText = "請執行 yabomish.sh 安裝 YabomishPrefs.app 到 /Applications。"
            a.runModal()
            return
        }
        // 從輸入法（背景 LSUIElement 行程）啟動 App，NSWorkspace.openApplication
        // 在某些 App（如 Ghostty）下無法前景化。改用 `open` 指令走
        // LaunchServices，可靠地觸發 applicationShouldHandleReopen →
        // NSApp.activate(ignoringOtherApps: true)。
        let proc = Process()
        proc.launchPath = "/usr/bin/open"
        proc.arguments = [appPath]
        try? proc.run()
    }

    private static var lastAppliedKeyboardLayout: String?

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        _ = Self.inputSourceObserver
        let targetLayout = "com.apple.keylayout.ABC"
        if let client = sender as? IMKTextInput {
            client.overrideKeyboard(withKeyboardNamed: targetLayout)
        }
        if Self.cinTable.isEmpty && !CINImportCoordinator.hasPromptedImport {
            CINImportCoordinator.hasPromptedImport = true
            panel.showGuide("尚未匯入字表 — 右鍵狀態列圖示 → 偏好設定 → 匯入字表")
            DispatchQueue.main.async { Self.promptImportCIN() }
        }
        let fromOtherIM = !Self.yabomishWasActive
        Self.yabomishWasActive = true
        if fromOtherIM {
            DispatchQueue.global(qos: .userInitiated).async {
                _ = WikiCorpus.shared
                _ = BigramSuggest.shared
                ZhuyinLookup.shared.preheat()
                _ = Self.cinTable.shortestCodesTable
            }
        }
        Self.activeSession = self
        panel.onCandidateSelected = { [weak self] text in
            guard let self else { return }
            let idx = self.candidateIndex(of: text)
            self.engine.selectCandidate(at: idx)
        }
        // Reset engine state for new session
        engine.handleEscape()
        engine.clearCandidates()
        if fromOtherIM && YabomishPrefs.showActivateToast {
            showModeToast(engine.currentModeLabel)
        }
        if CINImportCoordinator.showFirstUseTip {
            CINImportCoordinator.showFirstUseTip = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.showModeToast("空白鍵送字 ｜ Shift 切英文 ｜ ,,H 說明")
            }
        }
        #if !MINIMAL
        // 網路版（dl）安裝：首次啟用自動下載語料。完成後即時重載，不需重啟輸入法。
        // 失敗時靜默（僅記錄），下次啟用自動重試；離線時打字／查碼不受影響。
        if !DataDownloader.isDataAvailable {
            showModeToast("下載聯想語料中…")
            DataDownloader.ensureData { [weak self] ok in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    guard ok else {
                        DebugLog.log("YabomishIM: 語料尚未下載，聯想/重排功能停用")
                        return
                    }
                    self.engine.reloadSuggestionCorpus()
                    self.showModeToast("聯想語料就緒")
                }
            }
        }
        #endif
    }

    override func deactivateServer(_ sender: Any!) {
        guard Self.activeSession === self else {
            super.deactivateServer(sender)
            return
        }
        if let client = sender as? (NSObjectProtocol & IMKTextInput) {
            if engine.isZhuyinMode || engine.isPinyinMode {
                if engine.isZhuyinMode { engine.exitZhuyinMode() }
                if engine.isPinyinMode { engine.exitPinyinMode() }
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            } else if !engine.composing.isEmpty {
                // 切換視窗／輸入法時丟棄組字（多數 IM 慣例：未確認的字不代送）。
                // 舊行為有候選時以空白鍵代送第一候選，使用者切個視窗字就憑空落底文。
                engine.handleEscape()
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            }
        }
        panel.hide()
        Self.freqTracker.flushAll()
        Self.activeSession = nil
        super.deactivateServer(sender)
    }

    // MARK: - CIN Import (delegates to CINImportCoordinator)

    static func promptImportCIN() { CINImportCoordinator.promptImportCIN() }
    static func reloadTable() { CINImportCoordinator.reloadTable() }
    static func importCIN(from url: URL, attachedTo window: NSWindow?) {
        CINImportCoordinator.importCIN(from: url, attachedTo: window)
    }
    static func importCIN(attachedTo window: NSWindow? = nil) {
        CINImportCoordinator.importCIN(attachedTo: window)
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
        let e = InputEngine(cinTable: Self.cinTable, freqTracker: Self.freqTracker)
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
            // 萬用碼先於數字分支：組字中 Shift+8 一律萬用碼（不受 shiftDigitOutput 偏好影響）。
            // 原本數字分支在前，會把 Shift+8 攔成「送出第一候選＋插入字面 8」，萬用碼幾乎不可達。
            if keyCode == 28 && !engine.composing.isEmpty {
                engine.handleWildcard()
                return true
            }
            // Shift+digit while candidates showing: symbol (default) or digit per pref
            if let digit = keyCodeToDigit[keyCode], !engine.currentCandidates.isEmpty {
                if !engine.composing.isEmpty {
                    commitOrEscapeComposing()
                } else {
                    engine.clearCandidates()
                    panel.hide()
                }
                let out = YabomishPrefs.shiftDigitOutput == "digit"
                    ? String(digit)
                    : String(keyCodeToShifted[keyCode] ?? digit)
                client.insertText(out, replacementRange: notFoundRange)
                return true
            }
            if keyCode == 49 {
                commitOrEscapeComposing()
                client.insertText("\u{3000}", replacementRange: notFoundRange)
                return true
            }
            commitOrEscapeComposing()
            if let ch = keyCodeToChar[keyCode], ch.isLetter {
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
            if engine.composing.isEmpty {
                // 純聯想顯示（組字已空）：空白鍵輸出空白，並比照 Enter 收掉提示
                if !engine.currentCandidates.isEmpty {
                    engine.clearCandidates()
                    panel.hide()
                }
                return false
            }
            engine.handleSpace()
            return true
        case 51: // Backspace
            if engine.composing.isEmpty { return false }
            engine.handleBackspace()
            return true
        case 53: // Escape
            if engine.composing.isEmpty {
                // Exit special modes (same-sound, zhuyin, pinyin) even when composing is empty
                if engine.isInSpecialMode {
                    engine.handleEscape()
                    return true
                }
                if !engine.currentCandidates.isEmpty || panel.isVisible_ {
                    engine.clearCandidates()
                    panel.hide()
                    return true
                }
                return false
            }
            engine.handleEscape()
            return true
        case 36: // Enter
            if engine.composing.isEmpty && engine.currentCandidates.isEmpty { return false }
            if engine.composing.isEmpty && !engine.currentCandidates.isEmpty {
                // 純聯想顯示（組字已空）：Enter 不代選第一個聯想詞 —
                // 收掉提示、把換行原樣還給 app。選詞請用數字鍵或空白鍵以外的
                // 導航＋選取；Escape 亦可收掉提示
                engine.clearCandidates()
                panel.hide()
                return false
            }
            engine.handleEnter()
            return true
        default: break
        }

        // Arrow keys
        if panel.isVisible_ && (keyCode >= 123 && keyCode <= 126) {
            if engine.composing.isEmpty && engine.currentCandidates.isEmpty {
                engine.clearCandidates()
                panel.hide()
                return false
            }
            if navigateCandidates(keyCode) { return true }
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
                let idx = candidateIndex(of: selected)
                engine.selectCandidate(at: idx)
                return true
            }
        }

        // Non-CIN punctuation passthrough: - = \ ` ' ; /
        let passthroughKeyCodes: Set<UInt16> = [27, 24, 42, 50, 39, 41, 44]
        if passthroughKeyCodes.contains(keyCode) {
            commitOrEscapeComposing()
            if let sh = keyCodeToShifted[keyCode], flags.contains(.shift) {
                client.insertText(String(sh), replacementRange: notFoundRange)
            } else if let ch = keyCodeToChar[keyCode] {
                client.insertText(String(ch), replacementRange: notFoundRange)
            }
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

    /// 於目前候選中查找指定文字的索引；找不到時回退 0（沿用原行為）。
    private func candidateIndex(of text: String) -> Int {
        engine.currentCandidates.firstIndex(of: text) ?? 0
    }

    /// 直出按鍵前清場：有組字內容時，有候選以空白送出首選，否則跳離組字。
    private func commitOrEscapeComposing() {
        if !engine.composing.isEmpty {
            if !engine.currentCandidates.isEmpty { engine.handleSpace() }
            else { engine.handleEscape() }
        }
    }

    /// 方向鍵導候選。固定模式（或游標水平跟隨）：左右移動、上下翻頁；
    /// 直式（游標跟隨）：上下移動、左右翻頁。回傳是否已由導向處理。
    @discardableResult
    private func navigateCandidates(_ keyCode: UInt16) -> Bool {
        if panel.isFixedMode || YabomishPrefs.cursorHorizontal {
            switch keyCode {
            case 123: panel.movePrev(); return true
            case 124: panel.moveNext(); return true
            case 126: panel.pageUp(); return true
            case 125: panel.pageDown(); return true
            default: return false
            }
        } else {
            switch keyCode {
            case 126: panel.moveUp(); return true
            case 125: panel.moveDown(); return true
            case 123: panel.pageUp(); return true
            case 124: panel.pageDown(); return true
            default: return false
            }
        }
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
                if !engine.composing.isEmpty { engine.handleEscape() }
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
                let idx = candidateIndex(of: selected)
                engine.selectCandidate(at: idx)
                return true
            }
            if keyCode == 49 { panel.pageDown(); return true }
            if navigateCandidates(keyCode) { return true }
            if keyCode == 48 { panel.pageDown(); return true }
            if keyCode == 36 {
                // 無反白（純聯想顯示＋預選關閉）時 Enter 不代選，換行還給 app
                if let sel = panel.selectedCandidate() {
                    let idx = candidateIndex(of: sel)
                    engine.selectCandidate(at: idx)
                } else {
                    engine.clearCandidates()
                    panel.hide()
                    return false
                }
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
                let idx = candidateIndex(of: selected)
                engine.selectPinyinCandidate(at: idx)
                return true
            }
            if keyCode == 49 { panel.pageDown(); return true }
            if navigateCandidates(keyCode) { return true }
            if keyCode == 48 { panel.pageDown(); return true }
            if keyCode == 36 {
                // 無反白（純聯想顯示＋預選關閉）時 Enter 不代選，換行還給 app
                if let sel = panel.selectedCandidate() {
                    let idx = candidateIndex(of: sel)
                    engine.selectPinyinCandidate(at: idx)
                } else {
                    engine.clearCandidates()
                    panel.hide()
                    return false
                }
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
        // IMK offset 以 UTF-16 code unit 計算，非 text.count（Character 數）
        client.setMarkedText(marked, selectionRange: NSRange(location: text.utf16.count, length: 0),
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
        if output.utf16.count > range.length && range.length > 0 {
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
            // sel.location 為 UTF-16 offset，回退量須以 UTF-16 計算
            client.setMarkedText("", selectionRange: NSRange(location: sel.location - right.utf16.count, length: 0),
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

    func engineDidShowCodeHint(_ text: String, duration: Double) {
        showCodeHintToast(text, duration: duration)
    }

    func engineDidDeleteBack() {
        guard let client = engineClient else { return }
        let sel = client.selectedRange()
        // 刪除單位以最後送出字的 UTF-16 長度計算，避免刪除代理對（emoji 等）的一半
        let unit = max(1, engine._lastCommittedText.utf16.count)
        if sel.location != NSNotFound && sel.location >= unit {
            client.insertText("", replacementRange: NSRange(location: sel.location - unit, length: unit))
        }
    }

    func engineDidPasteText(_ text: String) {
        // Replace clipboard with processed text, then simulate Cmd+V
        // This preserves newlines better than insertText through IMK
        let pb = NSPasteboard.general
        // 覆蓋剪貼簿前先保存使用者原內容：逐 pasteboard item 記下所有型別的
        // 資料；原剪貼簿為空時 savedItems 為空陣列，稍後還原為空。
        var savedItems: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pb.pasteboardItems ?? [] {
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                // 跳過 promise 型別：data(forType:) 會同步向來源 app 索取資料，
                // 在打字熱路徑上可能卡頓，且還原後亦無法真正復原該能力
                if type.rawValue.contains("promised-") { continue }
                if let d = item.data(forType: type) { data[type] = d }
            }
            savedItems.append(data)
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        let ourChangeCount = pb.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let src = CGEventSource(stateID: .hidSystemState)
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            vDown?.flags = .maskCommand
            vUp?.flags = .maskCommand
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
        }
        // 貼上通常在數十毫秒內完成，留 0.5 秒緩衝後還原原剪貼簿。僅在
        // changeCount 仍為我們寫入的值時還原（期間使用者未複製其他內容，
        // 也不會和 Maccy 一類剪貼簿管理器的寫入互搶）。靜默還原，不顯示提示。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            guard NSPasteboard.general.changeCount == ourChangeCount else { return }
            NSPasteboard.general.clearContents()
            guard !savedItems.isEmpty else { return }
            let items: [NSPasteboardItem] = savedItems.map { saved in
                let it = NSPasteboardItem()
                for (type, data) in saved { it.setData(data, forType: type) }
                return it
            }
            NSPasteboard.general.writeObjects(items)
        }
    }

    func engineDidSuggest(_ suggestions: [String]) {
        guard let client = engineClient else { return }
        DebugLog.log("engineDidSuggest: \(suggestions.count) suggestions")
        if engine.composing.isEmpty && !suggestions.isEmpty {
            engine.setCandidates(suggestions)
            showNewEngineCandidatePanel(client: client)
        }
    }

    private func showNewEngineCandidatePanel(client: NSObjectProtocol & IMKTextInput) {
        let candidates = engine.currentCandidates
        guard !candidates.isEmpty else { panel.hide(); return }

        let markedLen = client.markedRange().length
        let cursorRect = Self.queryCursorRect(client: client, markedLength: markedLen > 0 ? markedLen : 0)

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
        // 純聯想顯示（組字已空）依偏好決定是否預先反白第一個候選；
        // 組字候選一律反白第一個
        let preselect = !engine.composing.isEmpty || YabomishPrefs.suggestPreselect
        panel.show(candidates: candidates, selKeys: engine.selKeys, at: origin, composing: engine.composing,
                   preselectFirst: preselect)
    }

    // MARK: - Cursor rect (OpenVanilla approach, fixes Chrome omnibox)

    private static func queryCursorRect(client: IMKTextInput, markedLength: Int) -> NSRect {
        // Primary: attributes(forCharacterIndex:lineHeightRectangle:)
        // Works in Chrome omnibox where firstRect returns garbage.
        var rect = NSRect.zero
        let idx = max(0, markedLength - 1)
        let attrs = client.attributes(forCharacterIndex: idx, lineHeightRectangle: &rect)
        if attrs != nil, !attrs!.isEmpty, rect != .zero {
            return rect
        }
        // Retry with index 0
        rect = .zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        if rect != .zero { return rect }
        // Fallback: firstRect (works in most apps)
        let sel = client.selectedRange()
        let range = sel.location != NSNotFound ? sel : NSRange(location: 0, length: 0)
        return client.firstRect(forCharacterRange: range, actualRange: nil)
    }
}
