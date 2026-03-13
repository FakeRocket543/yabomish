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
    33: "[", 30: "]",
]

/// Selection key keyCodes (number row: 1-9, 0)
private let keyCodeToDigit: [UInt16: Character] = [
    18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
    22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
]

/// Standard Zhuyin keyboard: keyCode → Zhuyin symbol
private let keyCodeToZhuyin: [UInt16: String] = [
    // Number row: 1→ㄅ, 2→ㄉ, 5→ㄓ, 8→ㄚ, 9→ㄞ, 0→ㄢ, -→ㄦ
    18: "ㄅ", 19: "ㄉ", 23: "ㄓ", 28: "ㄚ", 25: "ㄞ", 29: "ㄢ", 27: "ㄦ",
    // Q row
    12: "ㄆ", 13: "ㄊ", 14: "ㄍ", 15: "ㄐ", 17: "ㄔ", 16: "ㄗ",
    32: "ㄧ", 34: "ㄨ", 31: "ㄩ", 35: "ㄣ",
    // A row
    0: "ㄇ", 1: "ㄋ", 2: "ㄎ", 3: "ㄑ", 5: "ㄕ", 4: "ㄘ",
    38: "ㄛ", 40: "ㄜ", 37: "ㄠ", 41: "ㄤ",
    // Z row
    6: "ㄈ", 7: "ㄌ", 8: "ㄏ", 9: "ㄒ", 11: "ㄖ", 45: "ㄙ",
    46: "ㄝ", 43: "ㄟ", 47: "ㄡ", 44: "ㄥ",
]

/// Tone keyCodes: 3→ˇ, 4→ˋ, 6→ˊ, 7→˙  (space = tone 1)
private let keyCodeToTone: [UInt16: String] = [
    22: "ˊ", 20: "ˇ", 21: "ˋ", 26: "˙",
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
    private static let punctMap: [String: String] = [:]
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
    private var justCommitted = false
    private var isSameSoundMode = false
    private var sameSoundBase = ""  // the char selected in step 1

    // Zhuyin reverse lookup mode
    private var isZhuyinMode = false
    private var zhuyinBuffer = ""  // composed display string (auto-ordered)
    private var zyInitial = ""     // 聲母 slot
    private var zyMedial  = ""     // 介音 slot (ㄧㄨㄩ)
    private var zyFinal   = ""     // 韻母 slot

    private var selKeys: [Character] { Self.cinTable.selKeys }
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

        if event.type == .flagsChanged { return handleFlagsChanged(event) }

        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return false
        }

        // Hold Shift → temporary English input (lowercase)
        // Exception: Shift+8 = '*' wildcard when composing
        if flags.contains(.shift) && !flags.contains(.command) && !flags.contains(.control) && !flags.contains(.option) {
            if let chars = event.characters, chars == "*", !composing.isEmpty {
                shiftWasUsedWithOtherKey = true
                return handleWildcardInput(client: client)
            }
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

        // — Zhuyin reverse lookup mode —
        if isZhuyinMode {
            return handleZhuyinKey(keyCode, client: client)
        }

        // Punctuation → Chinese equivalents (when idle)
        if composing.isEmpty, let chars = event.characters {
            if let mapped = Self.punctMap[chars] {
                commitText(mapped, client: client)
                eatNextSpace = true
                return true
            }
        }

        // ' (single quote, keyCode 39) → same-sound mode
        if keyCode == 39 && !isSameSoundMode {
            // Mid-compose: commit first candidate then show same-sound list
            if !composing.isEmpty && !currentCandidates.isEmpty {
                let first = currentCandidates[0]
                commitText(first, client: client)
                isSameSoundMode = true
                sameSoundBase = first
                _ = handleSameSound(client: client)
                return true
            }
            if composing.isEmpty {
                // Post-commit: just committed a char → show same-sound list directly
                if justCommitted && !lastCommitted.isEmpty {
                    isSameSoundMode = true
                    sameSoundBase = lastCommitted
                    _ = handleSameSound(client: client)
                    return true
                }
                // Pre-commit: enter same-sound mode, type code to pick base char
                isSameSoundMode = true
                composing = "'"
                updateMarkedText(client: client)
                return true
            }
        }

        justCommitted = false

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
        // Arrow keys — navigate/page when candidate panel is visible
        if panel.isVisible_ && (keyCode == 123 || keyCode == 124 || keyCode == 125 || keyCode == 126) {
            if panel.isFixedMode {
                // Fixed (horizontal): ←→ navigate, ↑↓ page
                if keyCode == 123 { panel.movePrev(); return true }   // ←
                if keyCode == 124 { panel.moveNext(); return true }   // →
                if keyCode == 126 { panel.pageUp(); return true }     // ↑
                if keyCode == 125 { panel.pageDown(); return true }   // ↓
            } else {
                // Cursor-follow (vertical): ↑↓ navigate, ←→ page
                if keyCode == 126 { panel.moveUp(); return true }     // ↑
                if keyCode == 125 { panel.moveDown(); return true }   // ↓
                if keyCode == 123 { panel.pageUp(); return true }     // ←
                if keyCode == 124 { panel.pageDown(); return true }   // →
            }
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

        // VRSF: V/R/S/F select 2nd/3rd/4th/5th candidate when appending wouldn't form valid code
        let vrsfKeys: [(keyCode: UInt16, letter: String, index: Int)] = [
            (9, "v", 1), (15, "r", 2), (1, "s", 3), (3, "f", 4)
        ]
        for vk in vrsfKeys {
            if keyCode == vk.keyCode, currentCandidates.count > vk.index,
               !Self.cinTable.hasPrefix(composing + vk.letter) {
                commitText(currentCandidates[vk.index], client: client)
                return true
            }
        }

        // Selection keys (digits) when candidates showing
        if !currentCandidates.isEmpty, let digit = keyCodeToDigit[keyCode] {
            if let selected = panel.selectByKey(digit) {
                commitText(selected, client: client)
                return true
            }
        }

        // '/' passthrough when idle (useful for editor slash commands)
        if keyCode == 44 && composing.isEmpty { return false }

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
        // '; → toggle zhuyin mode (official Boshiamy shortcut)
        if isSameSoundMode && composing == "'" && char == ";" {
            isSameSoundMode = false
            composing = ""
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            isZhuyinMode.toggle()
            if isZhuyinMode {
                resetComposing(client: client)
                showModeToast("注")
            } else {
                clearZhuyinSlots()
                currentCandidates = []
                panel.hide()
                showModeToast("中")
            }
            return true
        }

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

        if currentCandidates.isEmpty && composing.count >= kMaxCodeLength && !isWildcard {
            NSSound.beep()
            resetComposing(client: client)
            return true
        }

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

    // MARK: - Zhuyin Reverse Lookup

    // 聲母 (21), 介音 (3), 韻母 (16)
    private static let zyInitials: Set<String> = [
        "ㄅ","ㄆ","ㄇ","ㄈ","ㄉ","ㄊ","ㄋ","ㄌ",
        "ㄍ","ㄎ","ㄏ","ㄐ","ㄑ","ㄒ",
        "ㄓ","ㄔ","ㄕ","ㄖ","ㄗ","ㄘ","ㄙ",
    ]
    private static let zyMedials: Set<String> = ["ㄧ","ㄨ","ㄩ"]
    private static let zyFinals: Set<String> = [
        "ㄚ","ㄛ","ㄜ","ㄝ","ㄞ","ㄟ","ㄠ","ㄡ",
        "ㄢ","ㄣ","ㄤ","ㄥ","ㄦ",
    ]

    /// Compose the three slots into canonical order: initial + medial + final
    private func composeZhuyin() -> String {
        zyInitial + zyMedial + zyFinal
    }

    /// Clear all zhuyin slots
    private func clearZhuyinSlots() {
        zyInitial = ""; zyMedial = ""; zyFinal = ""
        zhuyinBuffer = ""
    }

    /// Receive a zhuyin symbol and place it in the correct slot (replacing if occupied)
    private func receiveZhuyin(_ zy: String) {
        if Self.zyInitials.contains(zy) { zyInitial = zy }
        else if Self.zyMedials.contains(zy) { zyMedial = zy }
        else if Self.zyFinals.contains(zy) { zyFinal = zy }
        zhuyinBuffer = composeZhuyin()
    }

    /// Remove the last-entered component (right to left: final → medial → initial)
    private func backspaceZhuyin() {
        if !zyFinal.isEmpty { zyFinal = "" }
        else if !zyMedial.isEmpty { zyMedial = "" }
        else { zyInitial = "" }
        zhuyinBuffer = composeZhuyin()
    }

    private func handleZhuyinKey(_ keyCode: UInt16, client: IMKTextInput) -> Bool {
        // Escape → exit zhuyin mode
        if keyCode == 53 {
            if !zhuyinBuffer.isEmpty || !currentCandidates.isEmpty {
                clearZhuyinSlots()
                currentCandidates = []
                panel.hide()
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            } else {
                isZhuyinMode = false
                showModeToast("中")
            }
            return true
        }

        // Backspace
        if keyCode == 51 {
            if currentCandidates.isEmpty && !zhuyinBuffer.isEmpty {
                backspaceZhuyin()
                if zhuyinBuffer.isEmpty {
                    client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                         replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                } else {
                    updateMarkedText(zhuyinBuffer, client: client)
                }
            } else if !currentCandidates.isEmpty {
                currentCandidates = []
                panel.hide()
                updateMarkedText(zhuyinBuffer, client: client)
            }
            return true
        }

        // When candidates are showing: selection keys, navigation, space
        if !currentCandidates.isEmpty {
            if let digit = keyCodeToDigit[keyCode],
               let selected = panel.selectByKey(digit) {
                let char = String(selected.prefix(1))
                let codes = Self.cinTable.reverseLookup(char)
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                showCodeHintToast("\(char) → \(codes.joined(separator: " / "))")
                clearZhuyinSlots()
                currentCandidates = []
                panel.hide()
                return true
            }
            if keyCode == 49 { panel.pageDown(); return true }  // space = next page
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
            if keyCode == 48 { panel.pageDown(); return true }  // Tab
            // Enter → select highlighted
            if keyCode == 36, let sel = panel.selectedCandidate() {
                let char = String(sel.prefix(1))
                let codes = Self.cinTable.reverseLookup(char)
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                showCodeHintToast("\(char) → \(codes.joined(separator: " / "))")
                clearZhuyinSlots()
                currentCandidates = []
                panel.hide()
                return true
            }
            return true
        }

        // Tone key → finalize syllable and look up
        if let tone = keyCodeToTone[keyCode], !zhuyinBuffer.isEmpty {
            let zhuyin = tone == "˙" ? "˙" + zhuyinBuffer : zhuyinBuffer + tone
            return zhuyinLookup(zhuyin, client: client)
        }
        // Space → tone 1 (no mark)
        if keyCode == 49 && !zhuyinBuffer.isEmpty {
            return zhuyinLookup(zhuyinBuffer, client: client)
        }

        // Zhuyin symbol key
        if let zy = keyCodeToZhuyin[keyCode] {
            receiveZhuyin(zy)
            updateMarkedText(zhuyinBuffer, client: client)
            return true
        }

        return true  // eat all other keys in zhuyin mode
    }

    private func zhuyinLookup(_ zhuyin: String, client: IMKTextInput) -> Bool {
        let chars = ZhuyinLookup.shared.charsForZhuyin(zhuyin)
        guard !chars.isEmpty else { NSSound.beep(); return true }
        // Format: "字 碼" for each candidate
        currentCandidates = chars.map { char in
            let codes = Self.cinTable.reverseLookup(char)
            return codes.isEmpty ? char : "\(char) \(codes.joined(separator: "/"))"
        }
        updateMarkedText(zhuyin, client: client)
        showCandidatePanel(client: client)
        return true
    }

    private func updateMarkedText(_ text: String, client: IMKTextInput) {
        let attrs: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.textColor
        ]
        let marked = NSAttributedString(string: text, attributes: attrs)
        client.setMarkedText(marked, selectionRange: NSRange(location: text.count, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
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
        NSLog("YabomishIM: sameSound base=%@ readings=%d candidates=%d first10=%@",
              sameSoundBase, results.count, candidates.count,
              candidates.prefix(10).joined(separator: ","))
        currentCandidates = ZhuyinLookup.shared.sortByFreq(candidates)
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
        justCommitted = true
        if !composing.isEmpty && !isSameSoundMode {
            Self.freqTracker.record(code: composing, char: text)
            Self.freqTracker.recordBigram(prev: lastCommitted, char: text)
            Self.freqTracker.saveIfNeeded()
        }
        lastCommitted = text
        composing = ""
        currentCandidates = []
        isWildcard = false
        let wasSameSound = isSameSoundMode
        isSameSoundMode = false
        sameSoundBase = ""
        panel.hide()

        // 拆碼提示（同音字選字時一定顯示，且延長）
        if text.count == 1 {
            let codes = Self.cinTable.reverseLookup(text)
            if !codes.isEmpty && (wasSameSound || YabomishPrefs.showCodeHint) {
                showCodeHintToast("\(text) → \(codes.joined(separator: " / "))",
                                  duration: wasSameSound ? 3.0 : 1.2)
            }
        }
    }

    private func updateMarkedText(client: IMKTextInput) {
        updateMarkedText(composing, client: client)
    }

    private func resetComposing(client: IMKTextInput) {
        composing = ""
        currentCandidates = []
        isWildcard = false
        isSameSoundMode = false
        sameSoundBase = ""
        eatNextSpace = false
        clearZhuyinSlots()
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

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        let prefsItem = NSMenuItem(title: "偏好設定⋯", action: #selector(openPrefs), keyEquivalent: "")
        prefsItem.target = self
        menu.addItem(prefsItem)
        return menu
    }

    @objc private func openPrefs() {
        PrefsWindow.shared.showWindow()
    }

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
            isSameSoundMode = false
            sameSoundBase = ""
            justCommitted = false
            clearZhuyinSlots()
        }
    }

    override func deactivateServer(_ sender: Any!) {
        guard Self.activeSession === self else {
            super.deactivateServer(sender)
            return
        }
        if let client = sender as? (NSObjectProtocol & IMKTextInput) {
            if isZhuyinMode {
                clearZhuyinSlots()
                currentCandidates = []
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            } else if !composing.isEmpty && !currentCandidates.isEmpty {
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
