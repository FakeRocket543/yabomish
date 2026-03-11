import Cocoa
import InputMethodKit

private let kMaxCodeLength = 4

/// Hardware keyCode → QWERTY character mapping (layout-independent)
private let keyCodeToChar: [UInt16: Character] = [
    0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
    8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
    16: "y", 17: "t", 32: "u", 34: "i", 31: "o", 35: "p",
    38: "j", 40: "k", 37: "l", 45: "n", 46: "m",
    43: ",", 47: ".", 41: ";", 44: "/",
]

/// Selection key keyCodes (number row: 1-9, 0)
private let keyCodeToDigit: [UInt16: Character] = [
    18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
    22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
]

@objc(YabomishInputController)
class YabomishInputController: IMKInputController {

    // MARK: - Shared

    private static let cinTable: CINTable = {
        let t = CINTable()
        let userPath = NSHomeDirectory() + "/Library/YabomishIM/liu.cin"
        let bundlePath = Bundle.main.path(forResource: "liu", ofType: "cin")
        if FileManager.default.fileExists(atPath: userPath) { t.load(path: userPath) }
        else if let p = bundlePath { t.load(path: p) }
        else { NSLog("YabomishIM: No CIN table. Place liu.cin in ~/Library/YabomishIM/") }
        return t
    }()

    private static let freqTracker = FreqTracker()
    private static weak var activeSession: YabomishInputController?

    // MARK: - State

    private var composing = ""
    private var currentCandidates: [String] = []
    private var isWildcard = false
    private var isEnglishMode = false
    private var lastShiftDown: TimeInterval = 0
    private var shiftWasUsedWithOtherKey = false
    private var eatNextSpace = false
    private var lastCommitted = ""
    private var isSameSoundMode = false
    private var sameSoundBase = ""  // the char selected in step 1

    private var selKeys: [Character] { Self.cinTable.selKeys }
    private var panel: CandidatePanel { CandidatePanel.shared }

    // MARK: - Key Handling

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }
        guard event.type == .keyDown || event.type == .flagsChanged else { return false }
        guard let client = sender as? (NSObjectProtocol & IMKTextInput) else { return false }
        if IsSecureEventInputEnabled() { return false }

        if event.type == .flagsChanged { return handleFlagsChanged(event) }

        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return false
        }

        // Hold Shift → temporary English input (lowercase)
        if flags.contains(.shift) && !flags.contains(.command) && !flags.contains(.control) && !flags.contains(.option) {
            shiftWasUsedWithOtherKey = true
            if !composing.isEmpty {
                if !currentCandidates.isEmpty {
                    commitText(currentCandidates[0], client: client)
                } else {
                    resetComposing(client: client)
                }
            }
            if let ch = keyCodeToChar[keyCode] {
                let s = flags.contains(.capsLock) ? String(ch).uppercased() : String(ch)
                client.insertText(s, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                return true
            }
            return false
        }

        if isEnglishMode { return false }

        // ' (single quote, keyCode 39) → enter same-sound mode
        if keyCode == 39 && composing.isEmpty && !isSameSoundMode {
            isSameSoundMode = true
            composing = "'"
            updateMarkedText(client: client)
            return true
        }

        // Space
        if keyCode == 49 {
            if eatNextSpace { eatNextSpace = false; return true }
            return handleSpace(client: client)
        }
        eatNextSpace = false

        // Backspace
        if keyCode == 51 { return handleBackspace(client: client) }
        // Escape
        if keyCode == 53 { return handleEscape(client: client) }
        // Enter
        if keyCode == 36 {
            if sameSoundStep2, let sel = panel.selectedCandidate() {
                commitText(sel, client: client); return true
            }
            return handleEnter(client: client)
        }
        // Arrow keys (same-sound step 2)
        if sameSoundStep2 && panel.isVisible_ {
            if keyCode == 125 { panel.moveDown(); return true }   // ↓
            if keyCode == 126 { panel.moveUp(); return true }     // ↑
            if keyCode == 124 { panel.pageDown(); return true }   // →
            if keyCode == 123 { panel.pageUp(); return true }     // ←
        }
        // Tab
        if keyCode == 48 && panel.isVisible_ { panel.pageDown(); return true }
        // PageDown/Up
        if keyCode == 121 && panel.isVisible_ { panel.pageDown(); return true }
        if keyCode == 116 && panel.isVisible_ { panel.pageUp(); return true }

        // Wildcard: keyCode 44 is '/' on QWERTY but we use Shift+8 for '*'
        // Actually check characters for '*' since it's shift+8 on all layouts
        if let chars = event.characters, chars == "*", !composing.isEmpty {
            return handleWildcardInput(client: client)
        }

        // 補碼 v → select first candidate (when v can't extend the code)
        if keyCode == 9, !currentCandidates.isEmpty,
           !Self.cinTable.hasPrefix(composing + "v") {
            commitText(currentCandidates[0], client: client)
            return true
        }

        // Selection keys (digits) when candidates showing
        if !currentCandidates.isEmpty, let digit = keyCodeToDigit[keyCode] {
            if let selected = panel.selectByKey(digit) {
                commitText(selected, client: client)
                return true
            }
        }

        // Letter/punctuation keys — use keyCode for layout independence
        if let ch = keyCodeToChar[keyCode] {
            return handleLetterInput(String(ch), client: client)
        }

        return !composing.isEmpty
    }

    // MARK: - Shift Toggle

    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        let shiftDown = event.modifierFlags.contains(.shift)
        if shiftDown {
            lastShiftDown = event.timestamp
            shiftWasUsedWithOtherKey = false
        } else if lastShiftDown > 0 {
            if event.timestamp - lastShiftDown < 0.3 && !shiftWasUsedWithOtherKey {
                isEnglishMode.toggle()
                NSLog("YabomishIM: %@ mode", isEnglishMode ? "English" : "Chinese")
                showModeToast(isEnglishMode ? "A" : "中")
                if let client = self.client() { resetComposing(client: client) }
            }
            lastShiftDown = 0
        }
        return false
    }

    // MARK: - Input

    private func handleLetterInput(_ char: String, client: IMKTextInput) -> Bool {
        let newComposing = composing + char
        let maxLen = isSameSoundMode ? kMaxCodeLength + 1 : kMaxCodeLength

        if newComposing.count > maxLen {
            if !currentCandidates.isEmpty {
                commitText(currentCandidates[0], client: client)
                composing = char
                isWildcard = false
            } else {
                NSSound.beep()
                resetComposing(client: client)
                return true
            }
        } else {
            composing = newComposing
        }

        refreshCandidates()

        if YabomishPrefs.autoCommit &&
           currentCandidates.count == 1 && composing.count >= 2 && !canExtendCode(composing) {
            commitText(currentCandidates[0], client: client)
            eatNextSpace = true
            return true
        }

        updateMarkedText(client: client)
        showCandidatePanel(client: client)
        return true
    }

    private func handleWildcardInput(client: IMKTextInput) -> Bool {
        composing += "*"
        isWildcard = true
        currentCandidates = Self.cinTable.wildcardLookup(composing)
        updateMarkedText(client: client)
        showCandidatePanel(client: client)
        return true
    }

    private func handleSpace(client: IMKTextInput) -> Bool {
        if composing.isEmpty { return false }
        if sameSoundStep2 && panel.isVisible_ { panel.pageDown(); return true }
        if currentCandidates.isEmpty { NSSound.beep(); return true }
        commitText(currentCandidates[0], client: client)
        return true
    }

    private func handleEnter(client: IMKTextInput) -> Bool {
        if composing.isEmpty { return false }
        commitText(composing, client: client)
        return true
    }

    private func handleBackspace(client: IMKTextInput) -> Bool {
        if composing.isEmpty { return false }
        composing = String(composing.dropLast())
        if composing.isEmpty {
            resetComposing(client: client)
        } else {
            isWildcard = composing.contains("*")
            refreshCandidates()
            updateMarkedText(client: client)
            showCandidatePanel(client: client)
        }
        return true
    }

    private func handleEscape(client: IMKTextInput) -> Bool {
        if composing.isEmpty { return false }
        resetComposing(client: client)
        return true
    }

    // MARK: - Same-Sound Lookup

    private func handleSameSound(client: IMKTextInput) -> Bool {
        let results = ZhuyinLookup.shared.lookup(sameSoundBase)
        guard !results.isEmpty else { NSSound.beep(); resetComposing(client: client); return true }
        var candidates: [String] = []
        var seen = Set<String>()
        for r in results {
            for c in r.chars where seen.insert(c).inserted {
                candidates.append(c)
            }
        }
        currentCandidates = candidates
        composing = sameSoundBase
        // Keep marked text as the base char, panel position follows cursor
        updateMarkedText(client: client)
        showCandidatePanel(client: client)
        return true
    }

    /// In same-sound step 2, space = next page (not commit first candidate)
    private var sameSoundStep2: Bool {
        isSameSoundMode && !sameSoundBase.isEmpty
    }

    // MARK: - Mode Toast

    private static var modeWindow: NSPanel?

    private func showModeToast(_ text: String) {
        Self.modeWindow?.orderOut(nil)
        guard let screen = NSScreen.main else { return }
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 36, weight: .medium)
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

    // MARK: - Helpers

    private func canExtendCode(_ code: String) -> Bool {
        for ch in "abcdefghijklmnopqrstuvwxyz,.;/" {
            if Self.cinTable.hasPrefix(code + String(ch)) { return true }
        }
        return false
    }

    private func refreshCandidates() {
        let code = isSameSoundMode ? String(composing.dropFirst()) : composing
        let raw = isWildcard
            ? Self.cinTable.wildcardLookup(code)
            : Self.cinTable.lookup(code)
        currentCandidates = Self.freqTracker.sortedWithContext(raw, forCode: code, prev: lastCommitted)
    }

    private func commitText(_ text: String, client: IMKTextInput) {
        // Same-sound step 1: user picked the known char → show same-sound list
        if isSameSoundMode && sameSoundBase.isEmpty {
            sameSoundBase = text
            _ = handleSameSound(client: client)
            return
        }
        let range = client.markedRange()
        client.insertText(text, replacementRange: range)
        if !composing.isEmpty && !isSameSoundMode {
            Self.freqTracker.record(code: composing, char: text)
            Self.freqTracker.recordBigram(prev: lastCommitted, char: text)
            Self.freqTracker.saveIfNeeded()
        }
        lastCommitted = text
        composing = ""
        currentCandidates = []
        isWildcard = false
        isSameSoundMode = false
        sameSoundBase = ""
        panel.hide()
    }

    private func updateMarkedText(client: IMKTextInput) {
        let attrs: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.textColor
        ]
        let marked = NSAttributedString(string: composing, attributes: attrs)
        client.setMarkedText(marked, selectionRange: NSRange(location: composing.count, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    private func resetComposing(client: IMKTextInput) {
        composing = ""
        currentCandidates = []
        isWildcard = false
        isSameSoundMode = false
        sameSoundBase = ""
        eatNextSpace = false
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        panel.hide()
    }

    // MARK: - Candidate Panel

    /// Cache last known good cursor position so we can fall back when an app
    /// returns NSRect.zero (Terminal, some Electron apps, etc.)
    private static var lastGoodCursorOrigin: NSPoint?

    private func showCandidatePanel(client: IMKTextInput) {
        guard !currentCandidates.isEmpty else { panel.hide(); return }

        // Try to determine which screen the client app is on
        var cursorRect = NSRect.zero
        let range = client.selectedRange()
        client.attributes(forCharacterIndex: range.location, lineHeightRectangle: &cursorRect)

        if cursorRect.minX > 0 || cursorRect.minY > 0 {
            let pt = NSPoint(x: cursorRect.midX, y: cursorRect.midY)
            panel.targetScreen = NSScreen.screens.first(where: { $0.frame.contains(pt) })
        }

        let origin: NSPoint
        if YabomishPrefs.panelPosition == "fixed" {
            origin = .zero
        } else {
            if cursorRect.minX > 0 || cursorRect.minY > 0 {
                let pt = NSPoint(x: cursorRect.minX, y: cursorRect.minY)
                Self.lastGoodCursorOrigin = pt
                origin = pt
            } else if let cached = Self.lastGoodCursorOrigin {
                origin = cached
            } else {
                let screen = NSScreen.main?.visibleFrame ?? .zero
                origin = NSPoint(x: screen.midX - 40, y: screen.minY + 60)
            }
        }

        panel.show(candidates: currentCandidates, selKeys: selKeys, at: origin, composing: composing)
    }

    override func candidates(_ sender: Any!) -> [Any]! {
        currentCandidates as [Any]
    }

    // MARK: - Session

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        if let client = sender as? IMKTextInput {
            client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
        }
        if Self.activeSession !== self {
            Self.activeSession = self
            composing = ""
            currentCandidates = []
            isWildcard = false
            eatNextSpace = false
        }
    }

    override func deactivateServer(_ sender: Any!) {
        guard Self.activeSession === self else {
            super.deactivateServer(sender)
            return
        }
        if let client = sender as? (NSObjectProtocol & IMKTextInput) {
            if !composing.isEmpty && !currentCandidates.isEmpty {
                commitText(currentCandidates[0], client: client)
            } else if !composing.isEmpty {
                resetComposing(client: client)
            }
        }
        panel.hide()
        Self.activeSession = nil
        super.deactivateServer(sender)
    }
}
