import Foundation

/// Platform-independent input engine extracted from YabomishInputController.
/// The keyboard view controller calls methods here; the engine calls back via delegate.
protocol InputEngineDelegate: AnyObject {
    func engineDidUpdateComposing(_ text: String)
    func engineDidUpdateCandidates(_ candidates: [String])
    func engineDidCommit(_ text: String)
    func engineDidCommitPair(_ left: String, _ right: String)
    func engineDidClearComposing()
    func engineDidShowToast(_ text: String)
    func engineDidDeleteBack()
    func engineDidSuggest(_ suggestions: [String])
}

final class InputEngine {
    weak var delegate: InputEngineDelegate?

    let cinTable = CINTable()
    let freqTracker = FreqTracker()
    private let ranker = CandidateRanker()

    // MARK: - State

    private(set) var composing = ""
    var currentCandidates: [String] = []
    private var isWildcard = false
    private(set) var isEnglishMode = false
    private var lastCommitted = ""
    private var prevCommitted = ""
    private var recentCommitted = ""
    private var eatNextSpace = false

    // Snapshot for long-press undo
    private var snapComposing = ""
    private var snapCandidates: [String] = []
    private var snapIsWildcard = false

    // Same-sound
    private var isSameSoundMode = false
    private var sameSoundBase = ""

    // Zhuyin reverse lookup
    private(set) var isZhuyinMode = false
    private var zhuyinBuffer = ""
    private var zyInitial = "", zyMedial = "", zyFinal = ""

    // Pinyin reverse lookup
    private(set) var isPinyinMode = false
    private var pinyinSimplified = true
    private var pinyinBuffer = ""

    // ,, command
    private var commaCommandBuffer = ""
    private var isInCommaCommand = false

    // Input mode
    enum InputMode: String { case t, s, sp, sl, ts, st, j }
    private(set) var inputMode: InputMode = .t
    static let modeLabels: [InputMode: String] = [
        .t: "繁中", .s: "簡中", .sp: "速", .sl: "慢",
        .ts: "繁→簡", .st: "簡→繁", .j: "日"
    ]

    var selKeys: [Character] { cinTable.selKeys }
    var currentModeLabel: String { isEnglishMode ? "A" : (Self.modeLabels[inputMode] ?? "繁中") }

    // MARK: - Init

    func loadTable() {
        cinTable.reload()
    }

    func scheduleBackgroundTasks() {
        freqTracker.deferredMerge()
    }

    // MARK: - Public API (called by KeyboardViewController)

    func handleLetter(_ char: String) {
        snapComposing = composing; snapCandidates = currentCandidates; snapIsWildcard = isWildcard
        lastWasEmptySpace = false
        // '; → toggle zhuyin mode
        if isSameSoundMode && composing == "'" && char == ";" {
            isSameSoundMode = false; composing = ""
            delegate?.engineDidClearComposing()
            isZhuyinMode.toggle()
            delegate?.engineDidShowToast(isZhuyinMode ? "注" : currentModeLabel)
            if !isZhuyinMode { clearZhuyinSlots(); currentCandidates = []; notifyCandidates() }
            return
        }

        // Idle ' followed by letter → same-sound code input
        if isSameSoundMode && composing == "'" && sameSoundBase.isEmpty {
            if char >= "a" && char <= "z" || char == "*" {
                composing = "'" + char
                refreshCandidates()
                notifyComposing(); notifyCandidates(); return
            }
            isSameSoundMode = false; composing = ""
            delegate?.engineDidClearComposing()
            delegate?.engineDidCommit("、")
        }

        // ,, command: second comma
        if composing == "," && char == "," && !isSameSoundMode {
            isInCommaCommand = true; commaCommandBuffer = ""; composing = ",,"
            notifyComposing(); return
        }

        // ,, command: collecting
        if isInCommaCommand {
            commaCommandBuffer += char; composing = ",," + commaCommandBuffer
            notifyComposing(); return
        }

        let newComposing = composing + char
        let maxLen = isSameSoundMode ? cinTable.maxCodeLength + 1 : cinTable.maxCodeLength

        if newComposing.count > maxLen {
            if !currentCandidates.isEmpty {
                commitText(currentCandidates[0])
                composing = char; isWildcard = false
            } else {
                resetComposing(); return
            }
        } else {
            composing = newComposing
        }

        refreshCandidates()

        if currentCandidates.isEmpty && composing.count >= cinTable.maxCodeLength && !isWildcard {
            resetComposing(); return
        }

        if YabomishPrefs.autoCommit &&
           currentCandidates.count == 1 && composing.count >= 2 && !canExtendCode(composing) {
            commitText(currentCandidates[0]); eatNextSpace = true; return
        }

        notifyComposing(); notifyCandidates()
    }

    private var lastWasEmptySpace = false

    func handleSpace() {
        if composing.isEmpty { return }
        if eatNextSpace { eatNextSpace = false; return }
        // Double-space = escape (clear composing)
        if lastWasEmptySpace && currentCandidates.isEmpty {
            lastWasEmptySpace = false
            resetComposing(); delegate?.engineDidClearComposing(); return
        }
        lastWasEmptySpace = currentCandidates.isEmpty
        if isSameSoundMode && composing == "'" && sameSoundBase.isEmpty {
            isSameSoundMode = false; composing = ""
            delegate?.engineDidClearComposing()
            delegate?.engineDidCommit("、"); return
        }
        if isInCommaCommand {
            if commaCommandBuffer.isEmpty {
                isInCommaCommand = false; resetComposing()
                delegate?.engineDidCommit("\u{3000}"); return
            }
            dispatchCommaCommand(); return
        }
        if currentCandidates.isEmpty { return }
        commitText(currentCandidates[0])
    }

    func handleBackspace() {
        if isInCommaCommand {
            if commaCommandBuffer.isEmpty {
                isInCommaCommand = false; composing = ","
                notifyComposing()
            } else {
                commaCommandBuffer = String(commaCommandBuffer.dropLast())
                composing = ",," + commaCommandBuffer; notifyComposing()
            }
            return
        }
        if isZhuyinMode {
            if currentCandidates.isEmpty && !zhuyinBuffer.isEmpty {
                backspaceZhuyin()
                if zhuyinBuffer.isEmpty { delegate?.engineDidClearComposing() }
                else { delegate?.engineDidUpdateComposing(zhuyinBuffer) }
            } else if !currentCandidates.isEmpty {
                currentCandidates = []; notifyCandidates()
                delegate?.engineDidUpdateComposing(zhuyinBuffer)
            }
            return
        }
        if composing.isEmpty { return }
        composing = String(composing.dropLast())
        if composing.isEmpty { resetComposing() }
        else {
            isWildcard = composing.contains("*")
            refreshCandidates(); notifyComposing(); notifyCandidates()
        }
    }

    func handleEnter() {
        if isInCommaCommand { dispatchCommaCommand(); return }
        if composing.isEmpty { return }
        commitText(composing)
    }

    func handleEscape() {
        if isInCommaCommand { isInCommaCommand = false; commaCommandBuffer = "" }
        resetComposing()
    }

    func handleWildcard() {
        guard !composing.isEmpty else { return }
        composing += "*"; isWildcard = true
        currentCandidates = cinTable.wildcardLookup(composing)
        notifyComposing(); notifyCandidates()
    }

    /// Undo the last handleLetter call (for long-press number)
    func undoLastLetter() {
        // If autoCommit fired, undo the commit
        if composing != snapComposing && snapComposing.count < composing.count {
            // Normal case: just added a letter
            handleBackspace()
        } else if composing.count == 1 && snapComposing.isEmpty {
            // Added first letter
            handleBackspace()
        } else {
            // autoCommit or overflow happened — restore snapshot and undo commit
            delegate?.engineDidDeleteBack()
            composing = snapComposing; currentCandidates = snapCandidates; isWildcard = snapIsWildcard
            notifyComposing(); notifyCandidates()
        }
    }

    func selectCandidate(at index: Int) {
        NSLog("YabomishKB: selectCandidate idx=%d count=%d composing='%@' zhuyin=%d", index, currentCandidates.count, composing, isZhuyinMode ? 1 : 0)
        guard index < currentCandidates.count else { return }
        if isZhuyinMode {
            let full = currentCandidates[index]
            let char = String(full.prefix(1))
            let codes = cinTable.reverseLookup(char)
            commitText(char)
            if !codes.isEmpty { delegate?.engineDidShowToast("\(char) → \(codes.joined(separator: " / "))") }
            clearZhuyinSlots(); currentCandidates = []; notifyCandidates()
            // Auto-exit zhuyin after committing
            exitZhuyinMode()
        } else if composing.isEmpty {
            // Bigram suggestion — commit directly
            commitText(currentCandidates[index])
        } else {
            commitText(currentCandidates[index])
        }
    }

    /// VRSF quick-select: returns true if handled
    func handleVRSF(_ char: String) -> Bool {
        let map: [(String, Int)] = [("v", 1), ("r", 2), ("s", 3), ("f", 4)]
        for (letter, idx) in map {
            if char == letter && currentCandidates.count > idx && !cinTable.hasPrefix(composing + letter) {
                commitText(currentCandidates[idx]); return true
            }
        }
        return false
    }

    func selectByDigit(_ digit: Int) -> Bool {
        guard !currentCandidates.isEmpty else { return false }
        let keys = selKeys
        guard digit < keys.count else { return false }
        // digit 0 = first candidate on current page, etc.
        guard digit < currentCandidates.count else { return false }
        selectCandidate(at: digit)
        return true
    }

    func toggleEnglishMode() {
        isEnglishMode.toggle()
        if !isEnglishMode { /* switching back to Chinese */ }
        resetComposing()
        delegate?.engineDidShowToast(currentModeLabel)
    }

    /// Single-quote key: enter same-sound mode or output 頓號
    func handleQuote() {
        guard !isSameSoundMode && composing.isEmpty else { return }
        if !lastCommitted.isEmpty {
            isSameSoundMode = true; sameSoundBase = lastCommitted
            handleSameSound(); return
        }
        isSameSoundMode = true; composing = "'"
        notifyComposing()
    }

    func exitZhuyinMode() {
        guard isZhuyinMode else { return }
        isZhuyinMode = false
        clearZhuyinSlots(); currentCandidates = []; notifyCandidates()
        delegate?.engineDidShowToast(currentModeLabel)
    }

    // MARK: - Pinyin lookup

    func exitPinyinMode() {
        isPinyinMode = false; pinyinBuffer = ""
        currentCandidates = []; notifyCandidates()
        delegate?.engineDidClearComposing()
    }

    func handlePinyinLetter(_ ch: String) {
        guard isPinyinMode else { return }
        pinyinBuffer += ch
        composing = pinyinBuffer
        notifyComposing()
    }

    func handlePinyinTone(_ tone: Int) {
        guard isPinyinMode, !pinyinBuffer.isEmpty else { return }
        let pinyin = pinyinBuffer + "\(tone)"
        let chars = ZhuyinLookup.shared.charsForPinyin(pinyin)
        guard !chars.isEmpty else { return }
        let display: [String]
        if pinyinSimplified {
            let t2s = cinTable.t2s
            var seen = Set<String>()
            display = chars.compactMap { c in
                let s = t2s[c] ?? c; return seen.insert(s).inserted ? s : nil
            }
        } else { display = chars }
        currentCandidates = display.map { c in
            let codes = cinTable.reverseLookup(c)
            return codes.isEmpty ? c : "\(c) \(codes.joined(separator: "/"))"
        }
        composing = pinyin; notifyComposing(); notifyCandidates()
    }

    func handlePinyinSpace() {
        guard isPinyinMode else { return }
        if !pinyinBuffer.isEmpty { handlePinyinTone(1) }
    }

    func handlePinyinBackspace() {
        guard isPinyinMode else { return }
        if !currentCandidates.isEmpty {
            currentCandidates = []; notifyCandidates()
            composing = pinyinBuffer; notifyComposing()
        } else if !pinyinBuffer.isEmpty {
            pinyinBuffer = String(pinyinBuffer.dropLast())
            composing = pinyinBuffer; notifyComposing()
            if pinyinBuffer.isEmpty { delegate?.engineDidClearComposing() }
        }
    }

    func handlePinyinEscape() {
        guard isPinyinMode else { return }
        if !pinyinBuffer.isEmpty || !currentCandidates.isEmpty {
            pinyinBuffer = ""; currentCandidates = []; notifyCandidates()
            delegate?.engineDidClearComposing()
        } else {
            exitPinyinMode()
            delegate?.engineDidShowToast(currentModeLabel)
        }
    }

    func selectPinyinCandidate(at index: Int) {
        guard isPinyinMode, index < currentCandidates.count else { return }
        let entry = currentCandidates[index]
        let char = String(entry.prefix(1))
        delegate?.engineDidCommit(char)
        let codes = cinTable.reverseLookup(char)
        if !codes.isEmpty { delegate?.engineDidShowToast("\(char) → \(codes.joined(separator: " / "))") }
        pinyinBuffer = ""; currentCandidates = []; notifyCandidates()
        delegate?.engineDidClearComposing()
    }

    // MARK: - Zhuyin

    private static let zyInitials: Set<String> = [
        "ㄅ","ㄆ","ㄇ","ㄈ","ㄉ","ㄊ","ㄋ","ㄌ",
        "ㄍ","ㄎ","ㄏ","ㄐ","ㄑ","ㄒ","ㄓ","ㄔ","ㄕ","ㄖ","ㄗ","ㄘ","ㄙ",
    ]
    private static let zyMedials: Set<String> = ["ㄧ","ㄨ","ㄩ"]
    private static let zyFinals: Set<String> = [
        "ㄚ","ㄛ","ㄜ","ㄝ","ㄞ","ㄟ","ㄠ","ㄡ","ㄢ","ㄣ","ㄤ","ㄥ","ㄦ",
    ]

    func handleZhuyinSymbol(_ zy: String) {
        if Self.zyInitials.contains(zy) { zyInitial = zy }
        else if Self.zyMedials.contains(zy) { zyMedial = zy }
        else if Self.zyFinals.contains(zy) { zyFinal = zy }
        zhuyinBuffer = zyInitial + zyMedial + zyFinal
        delegate?.engineDidUpdateComposing(zhuyinBuffer)
    }

    func handleZhuyinTone(_ tone: String) {
        guard !zhuyinBuffer.isEmpty else { return }
        let zhuyin = tone == "˙" ? "˙" + zhuyinBuffer : zhuyinBuffer + tone
        zhuyinLookup(zhuyin)
    }

    func handleZhuyinSpace() {
        guard !zhuyinBuffer.isEmpty else { return }
        zhuyinLookup(zhuyinBuffer)  // tone 1
    }

    private func zhuyinLookup(_ zhuyin: String) {
        let raw = ZhuyinLookup.shared.charsForZhuyin(zhuyin)
        guard !raw.isEmpty else { return }
        let chars = ZhuyinLookup.shared.sortByFreq(raw, prevChar: prevCommitted, curZhuyin: zhuyin)
        currentCandidates = chars.map { char in
            let codes = cinTable.reverseLookup(char)
            return codes.isEmpty ? char : "\(char) \(codes.joined(separator: "/"))"
        }
        delegate?.engineDidUpdateComposing(zhuyin)
        notifyCandidates()
    }

    private func clearZhuyinSlots() {
        zyInitial = ""; zyMedial = ""; zyFinal = ""; zhuyinBuffer = ""
    }

    private func backspaceZhuyin() {
        if !zyFinal.isEmpty { zyFinal = "" }
        else if !zyMedial.isEmpty { zyMedial = "" }
        else { zyInitial = "" }
        zhuyinBuffer = zyInitial + zyMedial + zyFinal
    }

    // MARK: - Same-Sound

    private func handleSameSound() {
        let results = ZhuyinLookup.shared.lookup(sameSoundBase)
        NSLog("YabomishKB: handleSameSound base=%@ results=%d", sameSoundBase, results.count)
        guard let first = results.first else { resetComposing(); return }
        currentCandidates = ZhuyinLookup.shared.sortByFreq(first.chars)
        composing = sameSoundBase
        delegate?.engineDidUpdateComposing("\(sameSoundBase)[\(first.zhuyin)]")
        notifyCandidates()
    }

    // MARK: - ,, Command

    private func dispatchCommaCommand() {
        let cmd = commaCommandBuffer.lowercased()
        isInCommaCommand = false; commaCommandBuffer = ""
        resetComposing()

        let modeMap: [String: InputMode] = [
            "t": .t, "s": .s, "sp": .sp, "sl": .sl, "ts": .ts, "st": .st, "j": .j
        ]
        if cmd == "rs" { freqTracker.reset(); delegate?.engineDidShowToast("字頻已重置"); return }
        if cmd == "rl" { cinTable.reload(); delegate?.engineDidShowToast("字表已重載"); return }
        if cmd == "c" { delegate?.engineDidShowToast(currentModeLabel); return }
        if cmd == "zh" {
            isZhuyinMode.toggle()
            delegate?.engineDidShowToast(isZhuyinMode ? "注" : currentModeLabel)
            if !isZhuyinMode { clearZhuyinSlots(); currentCandidates = []; notifyCandidates() }
            return
        }
        if cmd == "h" {
            let help = """
            【Yabomish 輸入法 使用指南】

            ▎基本輸入
            • 輸入字根碼後按空白鍵送出
            • V/R/S/F 快速選第 2/3/4/5 個候選字
            • 數字鍵 1-9 選字（多候選時）

            ▎空白鍵手勢
            • 左右滑：循環切換 Yabomish→英文→數字→符號
            • 上滑：中↔英快速切換
            • 右上滑：注音查碼
            • 左上滑：同音字查詢

            ▎鍵盤切換
            • [123]：切到數字符號頁
            • [符]：切到數字頁（無蝦米第三行）
            • [嘸/英]：從數字符號頁回到字母頁

            ▎特殊指令（輸入 ,, 開頭）
            • ,,T 繁體  ,,S 簡體  ,,J 日文
            • ,,SP 速成  ,,SL 慢打
            • ,,TS 繁→簡  ,,ST 簡→繁
            • ,,ZH 注音查碼  ,,TO 同音字
            • ,,PYS 拼音(簡)  ,,PYT 拼音(繁)
            • ,,RS 重置字頻  ,,RL 重載字表
            • ,,C 顯示目前模式
            • ,,H 顯示本說明

            ▎候選字區
            • 空閒時顯示目前輸入法模式
            • 空閒時左方出現貼上鍵（剪貼簿有內容時）
            • 候選字超過 10 個時可展開為網格

            ▎高度調整
            • 拖拉候選字區上緣可調整鍵盤高度
            • 設定頁可用滑桿調整（以螢幕百分比儲存）
            """
            delegate?.engineDidCommit(help)
            return
        }
        if cmd == "pys" || cmd == "pyt" {
            let entering = !isPinyinMode || (cmd == "pys") != pinyinSimplified
            if entering {
                isPinyinMode = true; pinyinSimplified = (cmd == "pys")
                isZhuyinMode = false; clearZhuyinSlots()
                pinyinBuffer = ""; currentCandidates = []; notifyCandidates()
                delegate?.engineDidShowToast(cmd == "pys" ? "拼簡" : "拼繁")
            } else {
                isPinyinMode = false; pinyinBuffer = ""
                currentCandidates = []; notifyCandidates()
                delegate?.engineDidClearComposing()
                delegate?.engineDidShowToast(currentModeLabel)
            }
            return
        }
        if cmd == "to" {
            isSameSoundMode.toggle()
            if isSameSoundMode {
                sameSoundBase = ""; composing = "'"
                notifyComposing()
                delegate?.engineDidShowToast("同音字模式：打碼送字後列同音字")
            } else {
                sameSoundBase = ""; composing = ""
                delegate?.engineDidClearComposing()
                currentCandidates = []; notifyCandidates()
                delegate?.engineDidShowToast(currentModeLabel)
            }
            return
        }
        guard let mode = modeMap[cmd] else {
            delegate?.engineDidShowToast("未知命令 ,,\(cmd.uppercased())"); return
        }
        inputMode = mode
        delegate?.engineDidShowToast(Self.modeLabels[mode] ?? "繁中")
    }

    /// Switch to a named mode (used by space-swipe cycle). Returns the display label.
    @discardableResult
    func switchToMode(_ name: String) -> String {
        let modeMap: [String: InputMode] = [
            "t": .t, "s": .s, "sp": .sp, "sl": .sl, "ts": .ts, "st": .st, "j": .j
        ]
        if name == "zh" {
            if !isZhuyinMode { isZhuyinMode = true; clearZhuyinSlots() }
            isSameSoundMode = false; sameSoundBase = ""; composing = ""
            delegate?.engineDidShowToast("注")
            return "注"
        }
        if name == "to" {
            if !isSameSoundMode {
                isSameSoundMode = true; sameSoundBase = ""; composing = "'"
                notifyComposing()
            }
            if isZhuyinMode { exitZhuyinMode() }
            delegate?.engineDidShowToast("同音字模式")
            return "同"
        }
        // Regular input mode
        if isZhuyinMode { isZhuyinMode = false; clearZhuyinSlots(); currentCandidates = []; notifyCandidates() }
        if isSameSoundMode { isSameSoundMode = false; sameSoundBase = ""; composing = "" }
        if let mode = modeMap[name] {
            inputMode = mode
            let label = Self.modeLabels[mode] ?? "繁中"
            delegate?.engineDidShowToast(label)
            return label
        }
        return ""
    }

    /// Current mode identifier for cycle tracking
    var currentModeName: String {
        if isZhuyinMode { return "zh" }
        if isSameSoundMode { return "to" }
        return inputMode.rawValue
    }

    // MARK: - Internal

    private func canExtendCode(_ code: String) -> Bool {
        !cinTable.validNextKeys(after: code).isEmpty
    }

    public func validNextKeys() -> Set<Character> {
        guard !composing.isEmpty else { return [] }
        return cinTable.validNextKeys(after: composing)
    }

    private func refreshCandidates() {
        let code = isSameSoundMode ? String(composing.dropFirst()) : composing
        if inputMode == .j {
            currentCandidates = cinTable.lookup(code + ",") + cinTable.lookup(code + ".")
            return
        }
        let raw = isWildcard ? cinTable.wildcardLookup(code) : cinTable.lookup(code)
        currentCandidates = ranker.rank(raw: raw, code: code, prev: lastCommitted,
                                         mode: inputMode, cinTable: cinTable, freqTracker: freqTracker)

        // Fuzzy match: if no candidates, try adjacent-key substitution
        if currentCandidates.isEmpty && !isWildcard && code.count >= 2 && YabomishPrefs.fuzzyMatch {
            currentCandidates = ranker.fuzzyLookup(code, cinTable: cinTable)
        }
    }

    private static let punctuationPairs: [String: String] = [
        "「": "」", "（": "）", "『": "』", "【": "】", "《": "》", "〈": "〉",
    ]

    private func commitText(_ text: String) {
        NSLog("YabomishKB: commitText='%@' composing='%@' sameSound=%d", text, composing, isSameSoundMode ? 1 : 0)
        // Same-sound step 1 → step 2
        if isSameSoundMode && sameSoundBase.isEmpty && text.count == 1 {
            let results = ZhuyinLookup.shared.lookup(text)
            NSLog("YabomishKB: sameSound lookup char=%@ results=%d", text, results.count)
            if !results.isEmpty {
                sameSoundBase = text
                NSLog("YabomishKB: sameSound base=%@ zhuyin=%@ chars=%d", text, results.first?.zhuyin ?? "?", results.first?.chars.count ?? 0)
                handleSameSound(); return
            }
        }

        // Smart punctuation pairing
        if text.count == 1, let right = Self.punctuationPairs[text] {
            delegate?.engineDidCommitPair(text, right)
        } else {
            delegate?.engineDidCommit(text)
        }
        if !composing.isEmpty && !isSameSoundMode {
            freqTracker.record(code: composing, char: text)
            freqTracker.recordBigram(prev: lastCommitted, char: text)
            if !prevCommitted.isEmpty {
                freqTracker.recordTrigram(prev2: prevCommitted, prev1: lastCommitted, char: text)
            }
            freqTracker.saveIfNeeded()
        }
        prevCommitted = lastCommitted
        lastCommitted = text.count == 1 ? text : String(text.suffix(1))

        // Track recent committed text (for trigram + NER)
        recentCommitted += text
        if recentCommitted.count > 10 { recentCommitted = String(recentCommitted.suffix(10)) }
        let sentenceEnders: Set<Character> = ["。", "！", "？", ".", "!", "?", "\n", "；", ";"]
        if let last = text.last, sentenceEnders.contains(last) { recentCommitted = "" }

        composing = ""; currentCandidates = []
        isWildcard = false
        if isSameSoundMode {
            // Stay in same-sound mode — reset for next character
            sameSoundBase = ""; composing = "'"
            notifyComposing()
        } else {
            sameSoundBase = ""
        }
        notifyCandidates()

        if text.count == 1 && YabomishPrefs.showCodeHint && MemoryBudget.canAfford(MemoryBudget.reverseTable) {
            let codes = cinTable.reverseLookup(text)
            if !codes.isEmpty { delegate?.engineDidShowToast("\(text) → \(codes.joined(separator: " / "))") }
        }

        // 聯想
        if !isSameSoundMode && !isZhuyinMode {
            let results = SuggestionEngine.shared.suggest(recentCommitted: recentCommitted, lastText: text)
            if !results.isEmpty { delegate?.engineDidSuggest(results) }
        }
    }

    private func resetComposing() {
        composing = ""; currentCandidates = []; isWildcard = false
        isSameSoundMode = false; sameSoundBase = ""; eatNextSpace = false
        isInCommaCommand = false; commaCommandBuffer = ""
        clearZhuyinSlots()
        delegate?.engineDidClearComposing()
        notifyCandidates()
    }

    /// Returns the shortest code hint for a candidate, or nil if it equals the current composing.
    func shortestCodeHint(for char: String) -> String? {
        guard let codes = cinTable.shortestCodesTable[char] else { return nil }
        let best = codes.min(by: { $0.count < $1.count }) ?? codes.first!
        return best.count < composing.count ? best : nil
    }

    private func notifyComposing() { delegate?.engineDidUpdateComposing(composing) }
    private func notifyCandidates() { delegate?.engineDidUpdateCandidates(currentCandidates) }
}
