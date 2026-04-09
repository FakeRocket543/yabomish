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

    private static let cinTable: CINTable = {
        let t = CINTable()
        t.reload()
        if t.isEmpty { NSLog("YabomishIM: No CIN table. Place liu.cin in ~/Library/YabomishIM/") }
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

    // MARK: - State

    private var composing = ""
    private var currentCandidates: [String] = []
    private var isWildcard = false
    private var isEnglishMode = false
    private var lastShiftDown: TimeInterval = 0
    private var shiftWasUsedWithOtherKey = false
    private var eatNextSpace = false
    private var lastCommitted = ""
    /// 前兩個 commit 的字（用於 trigram 聯想）
    private var recentCommitted = ""
    private var justCommitted = false
    private var isHomophoneMode = false
    private var homophoneBase = ""  // the char selected in step 1

    // Zhuyin reverse lookup mode
    private var isZhuyinMode = false
    private var zhuyinBuffer = ""  // composed display string (auto-ordered)
    private var zyInitial = ""     // 聲母 slot
    private var zyMedial  = ""     // 介音 slot (ㄧㄨㄩ)
    private var zyFinal   = ""     // 韻母 slot

    // Pinyin reverse lookup mode
    private var isPinyinMode = false
    private var pinyinSimplified = true   // true=簡體 false=繁體
    private var pinyinBuffer = ""  // 使用者輸入的拼音字母

    // ,, command buffer
    private var commaCommandBuffer = ""   // collects chars after ",,"
    private var isInCommaCommand = false  // true after seeing ",,"
    private var lastHintedCode = ""       // SP/SL hint dedup

    // Input mode (,,T/,,S/,,SP/,,TS/,,ST/,,J)
    enum InputMode: String { case t, s, sp, sl, ts, st, j }
    private var inputMode: InputMode = .t
    private static let modeLabels: [InputMode: String] = [
        .t: "繁中", .s: "簡中", .sp: "速", .sl: "慢", .ts: "繁中→簡中", .st: "簡中→繁中", .j: "日"
    ]

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

        // T2: New engine feature flag
        if YabomishPrefs.useNewEngine {
            return handleWithNewEngine(event, client: client)
        }

        if event.type == .flagsChanged { return handleFlagsChanged(event) }

        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        DebugLog.log("key=\(keyCode) chars=\(event.characters ?? "") composing=\(composing) candidates=\(currentCandidates.count) zhuyin=\(isZhuyinMode) homophone=\(isHomophoneMode)")

        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return false
        }

        // 英文模式：用 keyCode 查表輸出 QWERTY 字元，不依賴系統鍵盤佈局
        // （避免法文 AZERTY 等非 QWERTY 佈局導致輸出錯位）
        if isEnglishMode {
            if flags.contains(.shift) { shiftWasUsedWithOtherKey = true }
            let wantShift = flags.contains(.shift) != flags.contains(.capsLock)
            // Shift+數字鍵 → 符號（!@#$%^&*()）
            if wantShift, let sh = keyCodeToShifted[keyCode] {
                client.insertText(String(sh), replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                return true
            }
            if let ch = keyCodeToChar[keyCode] ?? keyCodeToDigit[keyCode] {
                var s = String(ch)
                if wantShift { s = s.uppercased() }
                client.insertText(s, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                return true
            }
            return false
        }

        // Hold Shift → temporary English input (lowercase)
        // Exception: Shift+8 = '*' wildcard when composing
        // 用 keyCode 28 (數字鍵 8) 判斷，不依賴 event.characters（佈局無關）
        if flags.contains(.shift) && !flags.contains(.command) && !flags.contains(.control) && !flags.contains(.option) {
            if keyCode == 28, !composing.isEmpty {
                shiftWasUsedWithOtherKey = true
                return handleWildcardInput(client: client)
            }
            // Shift+Space → 全型空格
            if keyCode == 49 {
                shiftWasUsedWithOtherKey = true
                if !composing.isEmpty {
                    if !currentCandidates.isEmpty {
                        commitText(currentCandidates[0], client: client)
                    } else {
                        resetComposing(client: client)
                    }
                }
                commitText("\u{3000}", client: client)
                return true
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
            if let sh = keyCodeToShifted[keyCode] {
                client.insertText(String(sh), replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                return true
            }
            return false
        }

        // — Zhuyin reverse lookup mode —
        if isZhuyinMode {
            return handleZhuyinKey(keyCode, client: client)
        }

        // — Pinyin reverse lookup mode —
        if isPinyinMode {
            return handlePinyinKey(keyCode, client: client)
        }

        // ' (single quote, keyCode 39) → homophone mode
        if keyCode == 39 && !isHomophoneMode && composing.isEmpty {
            // Post-commit: just committed a char → show homophone list directly
            if justCommitted && !lastCommitted.isEmpty {
                isHomophoneMode = true
                homophoneBase = lastCommitted
                _ = handleHomophone(client: client)
                return true
            }
            // Idle: enter pending state for '; (zhuyin) detection
            // If next key is not ';', outputs 、 (頓號) instead
            isHomophoneMode = true
            composing = "'"
            updateMarkedText(client: client)
            return true
        }

        justCommitted = false

        // ,, command buffer: Space/Enter dispatches, Backspace/Escape cancels
        if isInCommaCommand {
            if keyCode == 49 || keyCode == 36 { // Space or Enter
                if commaCommandBuffer.isEmpty && keyCode == 49 {
                    isInCommaCommand = false
                    resetComposing(client: client)
                    commitText("\u{3000}", client: client)  // 全型空格
                    return true
                }
                return dispatchCommaCommand(client: client)
            }
            if keyCode == 51 { // Backspace
                if commaCommandBuffer.isEmpty {
                    isInCommaCommand = false
                    composing = ","
                    updateMarkedText(client: client)
                } else {
                    commaCommandBuffer = String(commaCommandBuffer.dropLast())
                    composing = ",," + commaCommandBuffer
                    updateMarkedText(client: client)
                }
                return true
            }
            if keyCode == 53 { // Escape
                isInCommaCommand = false
                commaCommandBuffer = ""
                resetComposing(client: client)
                return true
            }
            // Other keys handled in handleLetterInput (collecting chars)
        }

        // Space
        if keyCode == 49 {
            if eatNextSpace { eatNextSpace = false; return true }
            // Idle ' + space → output 、 (頓號)
            if isHomophoneMode && composing == "'" && homophoneBase.isEmpty {
                isHomophoneMode = false
                composing = ""
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                commitText("、", client: client)
                return true
            }
            return handleSpace(client: client)
        }
        eatNextSpace = false

        // Backspace
        if keyCode == 51 { return handleBackspace(client: client) }
        // Escape
        if keyCode == 53 { return handleEscape(client: client) }
        // Enter
        if keyCode == 36 {
            if homophoneStep2, let sel = panel.selectedCandidate() {
                commitText(sel, client: client); return true
            }
            return handleEnter(client: client)
        }
        // Arrow keys — navigate/page when candidate panel is visible
        // 聯想建議狀態（composing 為空）：方向鍵不攔截，讓使用者移動游標
        if panel.isVisible_ && (keyCode == 123 || keyCode == 124 || keyCode == 125 || keyCode == 126) {
            if composing.isEmpty {
                currentCandidates = []
                panel.hide()
                return false
            }
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

        // Wildcard: Shift+8 → '*'，用 keyCode 28 判斷（佈局無關，不依賴 event.characters）
        if keyCode == 28, flags.contains(.shift), !composing.isEmpty {
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

        // '/' passthrough when idle — 自己插入，避免法文鍵盤佈局錯位
        if keyCode == 44 && composing.isEmpty {
            client.insertText("/", replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            return true
        }

        // Letter/punctuation keys — use keyCode for layout independence
        if let ch = keyCodeToChar[keyCode] {
            return handleLetterInput(String(ch), client: client)
        }

        // Digits when idle: dismiss suggestions and output digit
        if composing.isEmpty, let digit = keyCodeToDigit[keyCode] {
            if !currentCandidates.isEmpty {
                currentCandidates = []
                panel.hide()
            }
            client.insertText(String(digit), replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            return true
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
                showModeToast(isEnglishMode ? "A" : (Self.modeLabels[inputMode] ?? "繁中"))
                if let client = self.client() { resetComposing(client: client) }
            }
            lastShiftDown = 0
        }
        return false
    }

    // MARK: - Input

    private func handleLetterInput(_ char: String, client: IMKTextInput) -> Bool {
        // '; → toggle zhuyin mode (official Boshiamy shortcut)
        if isHomophoneMode && composing == "'" && char == ";" {
            isHomophoneMode = false
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
                showModeToast(Self.modeLabels[inputMode] ?? "繁中")
            }
            return true
        }

        // Idle ' followed by non-; letter → enter homophone code input mode
        if isHomophoneMode && composing == "'" && homophoneBase.isEmpty {
            if char >= "a" && char <= "z" || char == "*" {
                // 同音字模式：收集編碼，送字後列同音字
                composing = "'" + String(char)
                refreshCandidates()
                updateMarkedText(client: client)
                showCandidatePanel(client: client)
                return true
            }
            // Non-letter: output 頓號 then process char normally
            isHomophoneMode = false
            composing = ""
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            commitText("、", client: client)
            // Fall through to process the char as normal input
        }

        // ,, command buffer: second comma triggers command mode
        if composing == "," && char == "," && !isHomophoneMode {
            isInCommaCommand = true
            commaCommandBuffer = ""
            composing = ",,"
            updateMarkedText(client: client)
            return true
        }

        // ,, command buffer: collecting command chars
        if isInCommaCommand {
            commaCommandBuffer += char
            composing = ",," + commaCommandBuffer
            updateMarkedText(client: client)
            return true
        }

        let newComposing = composing + char
        let baseMaxLen = Self.cinTable.maxCodeLength
        let maxLen = isHomophoneMode ? baseMaxLen + 1 : baseMaxLen

        if newComposing.count > maxLen {
            if YabomishPrefs.autoCommit && !currentCandidates.isEmpty {
                commitText(currentCandidates[0], client: client)
                composing = char
                isWildcard = false
            } else {
                NSSound.beep()
                if currentCandidates.isEmpty { resetComposing(client: client) }
                return true
            }
        } else {
            composing = newComposing
        }

        refreshCandidates()

        if currentCandidates.isEmpty && composing.count >= baseMaxLen && !isWildcard {
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
        if homophoneStep2 && panel.isVisible_ && composing == homophoneBase { panel.pageDown(); return true }
        if currentCandidates.isEmpty { NSSound.beep(); return true }
        let selected = panel.selectedCandidate() ?? currentCandidates[0]
        commitText(selected, client: client)
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
        // Dismiss suggestions if composing is empty but candidates showing
        if composing.isEmpty {
            if !currentCandidates.isEmpty {
                currentCandidates = []
                panel.hide()
                return true
            }
            return false
        }
        resetComposing(client: client)
        return true
    }

    // MARK: - ,, Command Dispatch

    private func dispatchCommaCommand(client: IMKTextInput) -> Bool {
        let cmd = commaCommandBuffer.lowercased()
        isInCommaCommand = false
        commaCommandBuffer = ""
        resetComposing(client: client)

        let modeMap: [String: InputMode] = [
            "t": .t, "s": .s, "sp": .sp, "sl": .sl, "ts": .ts, "st": .st, "j": .j
        ]

        // ,,RS → reset frequency data (special command, not a mode)
        if cmd == "rs" {
            Self.freqTracker.reset()
            showModeToast("字頻已重置\n候選字恢復預設順序")
            NSLog("YabomishIM: frequency data reset")
            return true
        }

        // ,,RL → reload CIN table + extras
        if cmd == "rl" {
            Self.cinTable.reload()
            showModeToast("字表已重載\n\(Self.cinTable.maxCodeLength) 碼")
            NSLog("YabomishIM: table reloaded, maxCodeLength=%d", Self.cinTable.maxCodeLength)
            return true
        }

        // ,,C → show current mode
        if cmd == "c" {
            let label = isEnglishMode ? "A" : (Self.modeLabels[inputMode] ?? "繁中")
            showModeToast(label)
            return true
        }

        // ,,ZH → toggle zhuyin lookup mode
        if cmd == "zh" {
            isZhuyinMode.toggle()
            if isZhuyinMode {
                isPinyinMode = false; pinyinBuffer = ""
                showModeToast("注")
            } else {
                clearZhuyinSlots()
                currentCandidates = []
                panel.hide()
                showModeToast(Self.modeLabels[inputMode] ?? "繁中")
            }
            return true
        }

        // ,,PYS / ,,PYT → pinyin lookup (simplified / traditional)
        if cmd == "pys" || cmd == "pyt" {
            let entering = !isPinyinMode || (cmd == "pys") != pinyinSimplified
            if entering {
                isPinyinMode = true
                pinyinSimplified = (cmd == "pys")
                isZhuyinMode = false; clearZhuyinSlots()
                pinyinBuffer = ""
                currentCandidates = []
                panel.hide()
                showModeToast(cmd == "pys" ? "拼簡" : "拼繁")
            } else {
                isPinyinMode = false
                pinyinBuffer = ""
                currentCandidates = []
                panel.hide()
                showModeToast(Self.modeLabels[inputMode] ?? "繁中")
            }
            return true
        }

        // ,,TO → enter homophone lookup mode
        if cmd == "to" {
            isHomophoneMode = true
            composing = "'"
            updateMarkedText(client: client)
            return true
        }

        // ,,H → show available commands
        if cmd == "h" {
            showCodeHintToast(",,T繁中 ,,S簡中 ,,SP速 ,,SL慢\n,,TS繁中→簡中 ,,ST簡中→繁中 ,,J日\n,,ZH注音查碼 ,,PYS拼音查碼(簡) ,,PYT拼音查碼(繁) ,,TO同音字\n,,RS重置字頻 ,,C當前模式 ,,H說明", duration: 4.0)
            return true
        }

        guard let mode = modeMap[cmd] else {
            showCodeHintToast("未知命令「,,\(cmd.uppercased())」\n,,H 查看說明", duration: 2.0)
            return true
        }
        // 檢查繁簡轉換表是否載入
        if (mode == .ts || mode == .s) && Self.cinTable.t2s.isEmpty {
            showCodeHintToast("⚠️ t2s.json 未載入", duration: 2.0)
        } else if mode == .st && Self.cinTable.s2t.isEmpty {
            showCodeHintToast("⚠️ s2t.json 未載入", duration: 2.0)
        }
        inputMode = mode
        showModeToast(Self.modeLabels[mode] ?? "繁中")
        NSLog("YabomishIM: mode → %@", mode.rawValue)
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
                showModeToast(Self.modeLabels[inputMode] ?? "繁中")
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
                // NER 詞組候選: [phrase] 格式
                if selected.hasPrefix("[") && selected.hasSuffix("]") {
                    let phrase = String(selected.dropFirst().dropLast())
                    commitText(phrase, client: client)
                } else {
                    let char = String(selected.prefix(1))
                    let codes = Self.cinTable.reverseLookup(char)
                    commitText(char, client: client)
                    showCodeHintToast("\(char) → \(codes.joined(separator: " / "))")
                }
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
                if sel.hasPrefix("[") && sel.hasSuffix("]") {
                    let phrase = String(sel.dropFirst().dropLast())
                    commitText(phrase, client: client)
                } else {
                    let char = String(sel.prefix(1))
                    let codes = Self.cinTable.reverseLookup(char)
                    commitText(char, client: client)
                    showCodeHintToast("\(char) → \(codes.joined(separator: " / "))")
                }
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
        let prevChar = lastCommitted.isEmpty ? nil : lastCommitted
        let chars = ZhuyinLookup.shared.charsForZhuyin(zhuyin, prevChar: prevChar)
        guard !chars.isEmpty else { NSSound.beep(); return true }

        // NER 詞組候選（多字詞排最前面）
        let phrases = PhraseLookup.shared.phrasesForZhuyin([zhuyin])
        let phraseCandidates = phrases.prefix(5).map { "[\($0.phrase)]" }

        // 單字候選
        let charCandidates = chars.map { char -> String in
            let codes = Self.cinTable.reverseLookup(char)
            return codes.isEmpty ? char : "\(char) \(codes.joined(separator: "/"))"
        }

        currentCandidates = Array(phraseCandidates) + charCandidates
        updateMarkedText(zhuyin, client: client)
        showCandidatePanel(client: client)
        return true
    }

    // MARK: - Pinyin reverse lookup

    private func handlePinyinKey(_ keyCode: UInt16, client: IMKTextInput) -> Bool {
        // Escape → exit pinyin mode
        if keyCode == 53 {
            if !pinyinBuffer.isEmpty || !currentCandidates.isEmpty {
                pinyinBuffer = ""
                currentCandidates = []
                panel.hide()
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            } else {
                isPinyinMode = false
                showModeToast(Self.modeLabels[inputMode] ?? "繁中")
            }
            return true
        }

        // Backspace
        if keyCode == 51 {
            if currentCandidates.isEmpty && !pinyinBuffer.isEmpty {
                pinyinBuffer = String(pinyinBuffer.dropLast())
                if pinyinBuffer.isEmpty {
                    client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                         replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                } else {
                    updateMarkedText(pinyinBuffer, client: client)
                }
            } else if !currentCandidates.isEmpty {
                currentCandidates = []
                panel.hide()
                updateMarkedText(pinyinBuffer, client: client)
            }
            return true
        }

        // When candidates are showing: selection keys, navigation, space
        if !currentCandidates.isEmpty {
            if let digit = keyCodeToDigit[keyCode],
               let selected = panel.selectByKey(digit) {
                let char = String(selected.prefix(1))
                let codes = Self.cinTable.reverseLookup(char)
                commitText(char, client: client)
                showCodeHintToast("\(char) → \(codes.joined(separator: " / "))")
                pinyinBuffer = ""
                currentCandidates = []
                panel.hide()
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
                let char = String(sel.prefix(1))
                let codes = Self.cinTable.reverseLookup(char)
                commitText(char, client: client)
                showCodeHintToast("\(char) → \(codes.joined(separator: " / "))")
                pinyinBuffer = ""
                currentCandidates = []
                panel.hide()
                return true
            }
            return true
        }

        // 數字鍵 1-5 → 聲調，觸發查詢
        if let digit = keyCodeToDigit[keyCode], let d = digit.wholeNumberValue, (1...5).contains(d), !pinyinBuffer.isEmpty {
            return pinyinLookup(pinyinBuffer + "\(d)", client: client)
        }
        // Space → 聲調 1（一聲）
        if keyCode == 49 && !pinyinBuffer.isEmpty {
            return pinyinLookup(pinyinBuffer + "1", client: client)
        }

        // 字母鍵 → 收集拼音
        if let ch = keyCodeToChar[keyCode], ch.isLetter {
            pinyinBuffer += String(ch)
            updateMarkedText(pinyinBuffer, client: client)
            return true
        }

        return true
    }

    private func pinyinLookup(_ pinyin: String, client: IMKTextInput) -> Bool {
        let chars = ZhuyinLookup.shared.charsForPinyin(pinyin)
        guard !chars.isEmpty else { NSSound.beep(); return true }
        let display: [String]
        if pinyinSimplified {
            let t2s = Self.cinTable.t2s
            var seen = Set<String>()
            display = chars.compactMap { char -> String? in
                let s = t2s[char] ?? char
                return seen.insert(s).inserted ? s : nil
            }
        } else {
            display = chars
        }
        currentCandidates = display.map { char in
            let codes = Self.cinTable.reverseLookup(char)
            return codes.isEmpty ? char : "\(char) \(codes.joined(separator: "/"))"
        }
        updateMarkedText(pinyin, client: client)
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

    // MARK: - Homophone Lookup

    private func handleHomophone(client: IMKTextInput) -> Bool {
        let results = ZhuyinLookup.shared.lookup(homophoneBase, prevChar: lastCommitted.isEmpty ? nil : lastCommitted)
        guard let first = results.first else { NSSound.beep(); resetComposing(client: client); return true }
        currentCandidates = first.chars
        composing = homophoneBase
        NSLog("YabomishIM: homophone base=%@ zhuyin=%@ candidates=%d",
              homophoneBase, first.zhuyin, currentCandidates.count)
        updateMarkedText("\(homophoneBase)[\(first.zhuyin)]", client: client)
        showCandidatePanel(client: client)
        return true
    }

    /// In homophone step 2, space = next page (not commit first candidate)
    private var homophoneStep2: Bool {
        isHomophoneMode && !homophoneBase.isEmpty
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
        let code = isHomophoneMode ? String(composing.dropFirst()) : composing

        // ,,J mode: auto-append , and . to look up hiragana/katakana
        if inputMode == .j {
            let hira = Self.cinTable.lookup(code + ",")
            let kata = Self.cinTable.lookup(code + ".")
            currentCandidates = hira + kata
            return
        }

        let raw = isWildcard
            ? Self.cinTable.wildcardLookup(code)
            : Self.cinTable.lookup(code)

        var candidates = Self.freqTracker.sortedWithContext(raw, forCode: code, prev: lastCommitted)

        switch inputMode {
        case .sp:
            // Only keep candidates whose shortest code(s) include current input
            let table = Self.cinTable.shortestCodesTable
            let spFiltered = candidates.filter { table[$0]?.contains(code) == true }
            if spFiltered.isEmpty && !candidates.isEmpty && lastHintedCode != code {
                lastHintedCode = code
                let hints = candidates.compactMap { ch -> String? in
                    guard let scs = table[ch], !scs.contains(code) else { return nil }
                    return "\(ch)→\(scs.sorted().first ?? "")"
                }
                if !hints.isEmpty {
                    showCodeHintToast(hints.prefix(5).joined(separator: "  "), duration: 2.0)
                }
            }
            candidates = spFiltered
        case .sl:
            // Only keep candidates whose longest code(s) include current input
            let table = Self.cinTable.longestCodesTable
            let slFiltered = candidates.filter { table[$0]?.contains(code) == true }
            if slFiltered.isEmpty && !candidates.isEmpty && lastHintedCode != code {
                lastHintedCode = code
                let hints = candidates.compactMap { ch -> String? in
                    guard let lcs = table[ch], !lcs.contains(code) else { return nil }
                    return "\(ch)→\(lcs.sorted().first ?? "")"
                }
                if !hints.isEmpty {
                    showCodeHintToast(hints.prefix(5).joined(separator: "  "), duration: 2.0)
                }
            }
            candidates = slFiltered
        case .ts:
            // 打繁出簡: convert trad→simp, dedup
            var seen = Set<String>()
            candidates = candidates.compactMap { ch in
                let s = Self.cinTable.convert(ch, map: Self.cinTable.t2s)
                return seen.insert(s).inserted ? s : nil
            }
        case .st:
            // 打簡出繁: convert simp→trad, dedup
            var seen = Set<String>()
            candidates = candidates.compactMap { ch in
                let t = Self.cinTable.convert(ch, map: Self.cinTable.s2t)
                return seen.insert(t).inserted ? t : nil
            }
        case .s:
            // 簡中模式: 只保留字表中本身就是簡體的字（存在於 t2s 值域，或繁簡同形）
            let t2s = Self.cinTable.t2s
            candidates = candidates.filter { ch in
                // 如果這個字不在 t2s 裡（繁簡同形），或者它本身就是簡體形式，保留
                guard let simplified = t2s[ch] else { return true }
                return simplified == ch
            }
        case .t, .j:
            break
        }

        // 領域感知：依社群上下文微調同碼字排序
        if YabomishPrefs.communityBoost && candidates.count > 1
            && PhraseLookup.shared.hasActiveContext && !code.hasPrefix(",") {
            let boosted = candidates.sorted { a, b in
                let ba = PhraseLookup.shared.communityBoost(for: a)
                let bb = PhraseLookup.shared.communityBoost(for: b)
                if ba != bb { return ba > bb }
                return false // 保持原排序
            }
            candidates = boosted
        }

        currentCandidates = candidates
    }

    private func commitText(_ text: String, client: IMKTextInput) {
        DebugLog.log("commit: \"\(text)\" composing=\(composing) homophone=\(isHomophoneMode) base=\(homophoneBase)")

        // Homophone step 1 → step 2: user picked a char via code, now show homophones
        if isHomophoneMode && homophoneBase.isEmpty && text.count == 1 {
            let results = ZhuyinLookup.shared.lookup(text, prevChar: lastCommitted.isEmpty ? nil : lastCommitted)
            if !results.isEmpty {
                homophoneBase = text
                _ = handleHomophone(client: client)
                return
            }
            // No homophones — fall through to normal commit
        }

        let range = client.markedRange()
        let output = text.replacingOccurrences(of: "\\n", with: "\n")
        // 長文字（擴充表詞條等）：先清 marked text 再插入，避免部分 App 以 markedRange length 截斷
        if output.count > range.length && range.length > 0 {
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                 replacementRange: range)
            client.insertText(output, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        } else {
            client.insertText(output, replacementRange: range)
        }
        justCommitted = true
        if !composing.isEmpty && !isHomophoneMode {
            Self.freqTracker.record(code: composing, char: text)
            Self.freqTracker.recordBigram(prev: lastCommitted, char: text)
            Self.freqTracker.saveIfNeeded()
        }
        lastCommitted = text
        composing = ""

        // 追蹤最近 commit 的文字（用於 trigram + NER）
        // 句子結束時重置上下文，避免跨句聯想
        recentCommitted += text
        if recentCommitted.count > 10 { recentCommitted = String(recentCommitted.suffix(10)) }
        let sentenceEnders: Set<Character> = ["。", "！", "？", ".", "!", "?", "\n", "；", ";"]
        if let last = text.last, sentenceEnders.contains(last) {
            recentCommitted = ""
        }

        // 更新社群上下文（Layer 3）
        PhraseLookup.shared.updateContext(committed: text)
        currentCandidates = []
        isWildcard = false
        let wasHomophone = isHomophoneMode
        isHomophoneMode = false
        homophoneBase = ""
        panel.hide()

        // 拆碼提示（同音字選字時一定顯示，且延長）
        if text.count == 1 {
            let codes = Self.cinTable.reverseLookup(text)
            if !codes.isEmpty && (wasHomophone || YabomishPrefs.showCodeHint) {
                showCodeHintToast("\(text) → \(codes.joined(separator: " / "))",
                                  duration: wasHomophone ? 3.0 : 1.2)
            }
        }

        // 聯想輸入：3 層合併（2-gram + 3-gram + NER 詞組補全）
        // 句子結束後不聯想；虛詞（的、了、在、是）後不聯想
        if !wasHomophone && !isZhuyinMode && YabomishPrefs.bigramSuggest && !recentCommitted.isEmpty {
            // NLTagger 詞性判斷：虛詞結尾跳過聯想
            let skipTags: Set<String> = ["Particle", "Preposition", "Conjunction", "Determiner"]
            let tagger = NLTagger(tagSchemes: [.lexicalClass])
            tagger.string = recentCommitted
            tagger.setLanguage(.traditionalChinese, range: recentCommitted.startIndex..<recentCommitted.endIndex)
            var lastTag: String?
            tagger.enumerateTags(in: recentCommitted.startIndex..<recentCommitted.endIndex, unit: .word, scheme: .lexicalClass) { tag, _ in
                lastTag = tag?.rawValue
                return true
            }
            if let tag = lastTag, skipTags.contains(tag) {
                // 虛詞結尾，不聯想
            } else {
            var suggestions: [String] = []
            var seen = Set<String>()

            // Layer 3: NER 詞組補全（最優先，只存尚未輸入的部分）
            if recentCommitted.count >= 2 {
                for len in [4, 3, 2] {
                    guard recentCommitted.count >= len else { continue }
                    let prefix = String(recentCommitted.suffix(len))
                    for phrase in PhraseLookup.shared.completions(for: prefix) {
                        let remainder = String(phrase.dropFirst(prefix.count))
                        if !remainder.isEmpty && seen.insert(remainder).inserted {
                            suggestions.append(remainder)
                        }
                        if suggestions.count >= 3 { break }
                    }
                    if suggestions.count >= 3 { break }
                }
            }

            // Layer 2: 3-gram（前兩字 → 下一字）
            if recentCommitted.count >= 2 {
                for ch in ZhuyinLookup.shared.suggestNextTrigram(prev2: recentCommitted) {
                    if seen.insert(ch).inserted { suggestions.append(ch) }
                }
            }

            // Layer 1: 2-gram（前一字 → 下一字）
            for ch in ZhuyinLookup.shared.suggestNext(after: text) {
                if seen.insert(ch).inserted { suggestions.append(ch) }
            }

            if !suggestions.isEmpty {
                // 領域感知：依社群上下文重排
                if YabomishPrefs.communityBoost && PhraseLookup.shared.hasActiveContext {
                    suggestions.sort { a, b in
                        PhraseLookup.shared.communityBoost(for: a) > PhraseLookup.shared.communityBoost(for: b)
                    }
                }
                currentCandidates = Array(suggestions.prefix(6))
                showCandidatePanel(client: client)
            }
            } // end NLTagger else
        }
    }

    private func updateMarkedText(client: IMKTextInput) {
        updateMarkedText(composing, client: client)
    }

    private func resetComposing(client: IMKTextInput) {
        composing = ""
        currentCandidates = []
        isWildcard = false
        isHomophoneMode = false
        homophoneBase = ""
        eatNextSpace = false
        isInCommaCommand = false
        commaCommandBuffer = ""
        lastHintedCode = ""
        clearZhuyinSlots()
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        panel.hide()
    }

    // MARK: - Candidate Panel

    private static var cachedActiveScreen: (screen: NSScreen, time: Date)?

    /// 取得 client app 所在螢幕（優先用滑鼠位置，fallback 到 CGWindowList）
    private func activeScreen(for client: IMKTextInput) -> NSScreen {
        if let cached = Self.cachedActiveScreen, Date().timeIntervalSince(cached.time) < 0.5 {
            return cached.screen
        }
        let result: NSScreen
        // 優先：滑鼠所在螢幕（打字時滑鼠通常在同一螢幕）
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            result = screen
        } else if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            // Fallback：找 frontmost app 面積最大的視窗（最可能是主視窗）
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

    private func showCandidatePanel(client: IMKTextInput) {
        guard !currentCandidates.isEmpty else { panel.hide(); return }

        // Try to determine which screen the client app is on
        var cursorRect = NSRect.zero
        let markedRange = client.markedRange()
        let queryRange: NSRange
        if markedRange.location != NSNotFound && markedRange.length > 0 {
            // 組字中：取 marked text 末端位置
            queryRange = NSRange(location: NSMaxRange(markedRange), length: 0)
        } else {
            queryRange = client.selectedRange()
        }
        // 回退重試策略：若 firstRect 回傳零座標，逐字往前退再試。
        // 參考自 vChewing-macOS 的 IMKTextInputImpl.swift
        // https://github.com/vChewing/vChewing-macOS
        if queryRange.location != NSNotFound {
            var loc = queryRange.location
            cursorRect = client.firstRect(forCharacterRange: queryRange, actualRange: nil)
            while cursorRect.origin == .zero && loc > 0 {
                loc -= 1
                cursorRect = client.firstRect(
                    forCharacterRange: NSRange(location: loc, length: 0), actualRange: nil)
            }
        }

        DebugLog.log("firstRect=\(cursorRect) queryRange=(\(queryRange.location),\(queryRange.length)) markedRange=(\(markedRange.location),\(markedRange.length))")

        let hasCursor: Bool = {
            guard cursorRect.minX > 0 || cursorRect.minY > 0
                  || cursorRect.size.height > 0 else { return false }
            let pt = NSPoint(x: cursorRect.midX, y: cursorRect.midY)
            return NSScreen.screens.contains(where: { $0.visibleFrame.contains(pt) })
        }()
        DebugLog.log("hasCursor=\(hasCursor) screens=\(NSScreen.screens.map { NSStringFromRect($0.visibleFrame) })")
        if hasCursor {
            let pt = NSPoint(x: cursorRect.midX, y: cursorRect.midY)
            panel.targetScreen = NSScreen.screens.first(where: { $0.frame.contains(pt) })
        }

        let origin: NSPoint
        if YabomishPrefs.panelPosition == "fixed" {
            panel.fallbackFixed = false
            origin = .zero
        } else if hasCursor {
            panel.fallbackFixed = false
            let pt = NSPoint(x: cursorRect.minX, y: cursorRect.minY)
            origin = pt
        } else {
            // 不相容 app（Terminal 等）：fallback 到固定模式
            panel.fallbackFixed = true
            let screen = activeScreen(for: client)
            panel.targetScreen = screen
            origin = .zero
        }

        panel.modeTag = Self.modeLabels[inputMode] ?? "繁中"
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

    private static var lastAppliedKeyboardLayout: String?

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        _ = Self.inputSourceObserver  // 確保 observer 已註冊
        // 防重複呼叫阻塞操作（參考 vChewing 的 lastAppliedKeyboardLayout 做法）
        let targetLayout = "com.apple.keylayout.ABC"
        if let client = sender as? IMKTextInput {
            client.overrideKeyboard(withKeyboardNamed: targetLayout)
        }
        // 首次啟動偵測空字表
        if Self.cinTable.isEmpty && !Self.hasPromptedImport {
            Self.hasPromptedImport = true
            DispatchQueue.main.async { Self.promptImportCIN() }
        }
        let fromOtherIM = !Self.yabomishWasActive
        Self.yabomishWasActive = true
        Self.activeSession = self
        panel.onCandidateSelected = { [weak self] text in
            guard let self, let client = self.client() else { return }
            self.commitText(text, client: client)
        }
        composing = ""
        currentCandidates = []
        isWildcard = false
        eatNextSpace = false
        isHomophoneMode = false
        homophoneBase = ""
        justCommitted = false
        recentCommitted = ""
        clearZhuyinSlots()
        if fromOtherIM && YabomishPrefs.showActivateToast {
            showModeToast(isEnglishMode ? "A" : (Self.modeLabels[inputMode] ?? "繁中"))
        }
        // 語料下載檢查（背景執行，不阻塞）
        if !DataDownloader.isDataAvailable {
            DataDownloader.ensureData { ok in
                if !ok { NSLog("YabomishIM: 語料尚未下載，聯想/重排功能停用") }
            }
        }
    }

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
        NSLog("YabomishIM: table reloaded via UI, maxCodeLength=%d", cinTable.maxCodeLength)
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
        // Must run on main thread for NSOpenPanel
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
            NSLog("YabomishIM: Imported CIN table from %@", src.path)
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
            } else if isPinyinMode {
                pinyinBuffer = ""
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
        Self.lastDeactivateTime = Date()
        super.deactivateServer(sender)
    }
}

// MARK: - T2: New InputEngine Integration

extension YabomishInputController {

    /// Weak reference to the current IMKTextInput client for delegate callbacks.
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
    /// Lazy InputEngine — only created when useNewEngine is true.
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

        // FlagsChanged: detect Shift double-tap
        if event.type == .flagsChanged {
            return handleNewEngineFlagsChanged(event)
        }

        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Pass through modifier combos
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return false
        }

        // English mode: output QWERTY chars directly
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
            // Shift+8 = wildcard when composing
            if keyCode == 28 && !engine.composing.isEmpty {
                engine.handleWildcard()
                return true
            }
            // Shift+Space = full-width space
            if keyCode == 49 {
                if !engine.composing.isEmpty {
                    if !engine.currentCandidates.isEmpty { engine.handleSpace() }
                    else { engine.handleEscape() }
                }
                client.insertText("\u{3000}", replacementRange: notFoundRange)
                return true
            }
            // Shift+letter = temporary English
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
                // Dismiss suggestions if showing
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

        // Arrow keys — panel navigation (only when panel visible and composing)
        if panel.isVisible_ && (keyCode >= 123 && keyCode <= 126) {
            if engine.composing.isEmpty {
                // Suggestion state: dismiss and pass through
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

        // Digit keys — select candidate (only when actively composing)
        if !engine.currentCandidates.isEmpty && !engine.composing.isEmpty, let digit = keyCodeToDigit[keyCode] {
            if let selected = panel.selectByKey(digit) {
                let idx = engine.currentCandidates.firstIndex(of: selected) ?? 0
                engine.selectCandidate(at: idx)
                return true
            }
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

        // Digits when idle — dismiss suggestions and output digit
        if engine.composing.isEmpty, let digit = keyCodeToDigit[keyCode] {
            if !engine.currentCandidates.isEmpty {
                engine.clearCandidates()
                panel.hide()
            }
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
        if keyCode == 51 { engine.handleBackspace(); return true } // Backspace

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
        // Space = tone 1
        if keyCode == 49 { engine.handleZhuyinSpace(); return true }

        // Zhuyin symbol
        if let zy = keyCodeToZhuyin[keyCode] {
            engine.handleZhuyinSymbol(zy)
            return true
        }

        return true // eat all other keys in zhuyin mode
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
        // Space = tone 1
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
        // Move cursor between the pair
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

    /// Show candidate panel reading from engine state (not controller state).
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
