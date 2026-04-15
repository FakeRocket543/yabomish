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

    let cinTable: CINTable
    let freqTracker: FreqTracker
    private let ranker: CandidateRanker
    private let zhuyinLookup: ZhuyinLookup
    private let suggestionEngine: SuggestionEngine
    private let prefs: IMEPreferences
    private let lock = NSRecursiveLock()

    private func sync<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    init(cinTable: CINTable? = nil,
         freqTracker: FreqTracker? = nil,
         zhuyinLookup: ZhuyinLookup = .shared,
         suggestionEngine: SuggestionEngine = .shared,
         wikiCorpus: WikiCorpus = .shared,
         prefs: IMEPreferences = DefaultPreferences.shared) {
        self.cinTable = cinTable ?? CINTable()
        self.freqTracker = freqTracker ?? FreqTracker()
        self.zhuyinLookup = zhuyinLookup
        self.suggestionEngine = suggestionEngine
        self.prefs = prefs
        self.ranker = CandidateRanker(wikiCorpus: wikiCorpus, prefs: prefs)
    }

    // MARK: - State

    private var _composing = ""
    private var _currentCandidates: [String] = []
    private var _isWildcard = false
    private var _isEnglishMode = false
    private var _lastCommitted = ""
    var _lastCommittedText: String { _lastCommitted }
    private var _prevCommitted = ""
    private var _recentCommitted = ""
    private var _eatNextSpace = false

    // Snapshot for long-press undo
    private var _snapComposing = ""
    private var _snapCandidates: [String] = []
    private var _snapIsWildcard = false

    // Same-sound
    private var _isSameSoundMode = false
    private var _sameSoundBase = ""

    // Zhuyin reverse lookup
    private var _isZhuyinMode = false
    private var _zhuyinBuffer = ""
    private var _zyInitial = "", _zyMedial = "", _zyFinal = ""

    // Pinyin reverse lookup
    private var _isPinyinMode = false
    private var _pinyinSimplified = true
    private var _pinyinBuffer = ""

    // ,, command
    private var _commaCommandBuffer = ""
    private var _isInCommaCommand = false

    // Input mode
    enum InputMode: String { case t, s, sp, sl, ts, st, j }
    private var _inputMode: InputMode = .t
    static let modeLabels: [InputMode: String] = [
        .t: "繁中", .s: "簡中", .sp: "速", .sl: "慢",
        .ts: "繁→簡", .st: "簡→繁", .j: "日"
    ]

    // MARK: - Thread-safe public accessors

    var composing: String { sync { _composing } }
    var currentCandidates: [String] { sync { _currentCandidates } }
    var isEnglishMode: Bool { sync { _isEnglishMode } }
    var isZhuyinMode: Bool { sync { _isZhuyinMode } }
    var isPinyinMode: Bool { sync { _isPinyinMode } }
    var inputMode: InputMode { sync { _inputMode } }
    var selKeys: [Character] { cinTable.selKeys }
    var currentModeLabel: String { sync { _isEnglishMode ? "A" : (Self.modeLabels[_inputMode] ?? "繁中") } }
    var currentModeName: String { sync { _currentModeName } }

    func clearCandidates() { sync { _currentCandidates = [] } }
    func setCandidates(_ c: [String]) { sync { _currentCandidates = c } }

    /// Internal computed (called from within queue)
    private var _currentModeName: String {
        if _isZhuyinMode { return "zh" }
        if _isSameSoundMode { return "to" }
        return _inputMode.rawValue
    }

    private var _currentModeLabel: String {
        _isEnglishMode ? "A" : (Self.modeLabels[_inputMode] ?? "繁中")
    }

    // MARK: - Init

    func loadTable() {
        cinTable.reload()
    }

    func scheduleBackgroundTasks() {
        freqTracker.deferredMerge()
    }

    // MARK: - Public API (called by KeyboardViewController)

    func handleLetter(_ char: String) { sync {
        _snapComposing = _composing; _snapCandidates = _currentCandidates; _snapIsWildcard = _isWildcard
        _lastWasEmptySpace = false

        // Same-sound mode: direct code input (no ' prefix)
        if _isSameSoundMode && _composing.isEmpty && _sameSoundBase.isEmpty {
            if char >= "a" && char <= "z" || char == "*" {
                _composing = String(char)
                _refreshCandidates()
                _notifyComposing(); _notifyCandidates(); return
            }
        }

        // ,, command: second comma
        if _composing == "," && char == "," && !_isSameSoundMode {
            _isInCommaCommand = true; _commaCommandBuffer = ""; _composing = ",,"
            _notifyComposing(); return
        }

        // ,, command: collecting
        if _isInCommaCommand {
            _commaCommandBuffer += char; _composing = ",," + _commaCommandBuffer
            _notifyComposing(); return
        }

        let newComposing = _composing + char
        let maxLen = cinTable.maxCodeLength

        if newComposing.count > maxLen {
            if !_currentCandidates.isEmpty {
                _commitText(_currentCandidates[0])
                _composing = char; _isWildcard = false
            } else {
                _resetComposing(); return
            }
        } else {
            _composing = newComposing
        }

        _refreshCandidates()

        if _currentCandidates.isEmpty && _composing.count >= cinTable.maxCodeLength && !_isWildcard {
            _resetComposing(); return
        }

        if prefs.autoCommit &&
           _currentCandidates.count == 1 && _composing.count >= 2 && !_canExtendCode(_composing) {
            _commitText(_currentCandidates[0]); _eatNextSpace = true; return
        }

        _notifyComposing(); _notifyCandidates()
    } }

    private var _lastWasEmptySpace = false

    func handleSpace() { sync {
        if _composing.isEmpty { return }
        if _eatNextSpace { _eatNextSpace = false; return }
        // Double-space = escape (clear composing)
        if _lastWasEmptySpace && _currentCandidates.isEmpty {
            _lastWasEmptySpace = false
            _resetComposing(); delegate?.engineDidClearComposing(); return
        }
        _lastWasEmptySpace = _currentCandidates.isEmpty
        if _isInCommaCommand {
            if _commaCommandBuffer.isEmpty {
                _isInCommaCommand = false; _resetComposing()
                delegate?.engineDidCommit("\u{3000}"); return
            }
            _dispatchCommaCommand(); return
        }
        if _currentCandidates.isEmpty { return }
        _commitText(_currentCandidates[0])
    } }

    func handleBackspace() { sync {
        if _isInCommaCommand {
            if _commaCommandBuffer.isEmpty {
                _isInCommaCommand = false; _composing = ","
                _notifyComposing()
            } else {
                _commaCommandBuffer = String(_commaCommandBuffer.dropLast())
                _composing = ",," + _commaCommandBuffer; _notifyComposing()
            }
            return
        }
        if _isZhuyinMode {
            if _currentCandidates.isEmpty && !_zhuyinBuffer.isEmpty {
                _backspaceZhuyin()
                if _zhuyinBuffer.isEmpty { delegate?.engineDidClearComposing() }
                else { delegate?.engineDidUpdateComposing(_zhuyinBuffer) }
            } else if !_currentCandidates.isEmpty {
                _currentCandidates = []; _notifyCandidates()
                delegate?.engineDidUpdateComposing(_zhuyinBuffer)
            }
            return
        }
        if _composing.isEmpty {
            if !_recentCommitted.isEmpty { _recentCommitted = String(_recentCommitted.dropLast()) }
            if !_currentCandidates.isEmpty { _currentCandidates = []; _notifyCandidates() }
            delegate?.engineDidDeleteBack()
            return
        }
        _composing = String(_composing.dropLast())
        if _composing.isEmpty { _resetComposing() }
        else {
            _isWildcard = _composing.contains("*")
            _refreshCandidates(); _notifyComposing(); _notifyCandidates()
        }
    } }

    func handleEnter() { sync {
        if _isInCommaCommand { _dispatchCommaCommand(); return }
        if _composing.isEmpty { return }
        _commitText(_composing)
    } }

    func handleEscape() { sync {
        if _isInCommaCommand { _isInCommaCommand = false; _commaCommandBuffer = "" }
        _isSameSoundMode = false
        _resetComposing()
    } }

    func handleWildcard() { sync {
        guard !_composing.isEmpty else { return }
        _composing += "*"; _isWildcard = true
        _currentCandidates = cinTable.wildcardLookup(_composing)
        _notifyComposing(); _notifyCandidates()
    } }

    /// Undo the last handleLetter call (for long-press number)
    func undoLastLetter() { sync {
        // If autoCommit fired, undo the commit
        if _composing != _snapComposing && _snapComposing.count < _composing.count {
            // Normal case: just added a letter
            _handleBackspaceImpl()
        } else if _composing.count == 1 && _snapComposing.isEmpty {
            // Added first letter
            _handleBackspaceImpl()
        } else {
            // autoCommit or overflow happened — restore snapshot and undo commit
            delegate?.engineDidDeleteBack()
            _composing = _snapComposing; _currentCandidates = _snapCandidates; _isWildcard = _snapIsWildcard
            _notifyComposing(); _notifyCandidates()
        }
    } }

    func selectCandidate(at index: Int) { sync {
        DebugLog.log("YabomishKB: selectCandidate idx=\(index) count=\(_currentCandidates.count) composing='\(_composing)' zhuyin=\(_isZhuyinMode ? 1 : 0)")
        guard index < _currentCandidates.count else { return }
        if _isZhuyinMode {
            let full = _currentCandidates[index]
            let char = String(full.prefix(1))
            let codes = cinTable.reverseLookup(char)
            _commitText(char)
            if !codes.isEmpty { delegate?.engineDidShowToast("\(char) → \(codes.joined(separator: " / "))") }
            _clearZhuyinSlots(); _currentCandidates = []; _notifyCandidates()
            // Auto-exit zhuyin after committing
            _exitZhuyinModeImpl()
        } else if _composing.isEmpty {
            // Bigram suggestion — commit directly
            _commitText(_currentCandidates[index])
        } else {
            _commitText(_currentCandidates[index])
        }
    } }

    /// VRSF quick-select: returns true if handled
    func handleVRSF(_ char: String) -> Bool { sync {
        let map: [(String, Int)] = [("v", 1), ("r", 2), ("s", 3), ("f", 4)]
        for (letter, idx) in map {
            if char == letter && _currentCandidates.count > idx && !cinTable.hasPrefix(_composing + letter) {
                _commitText(_currentCandidates[idx]); return true
            }
        }
        return false
    } }

    func selectByDigit(_ digit: Int) -> Bool { sync {
        guard !_currentCandidates.isEmpty else { return false }
        let keys = cinTable.selKeys
        guard digit < keys.count else { return false }
        // digit 0 = first candidate on current page, etc.
        guard digit < _currentCandidates.count else { return false }
        _selectCandidateImpl(at: digit)
        return true
    } }

    func toggleEnglishMode() { sync {
        _isEnglishMode.toggle()
        if !_isEnglishMode { /* switching back to Chinese */ }
        _resetComposing()
        delegate?.engineDidShowToast(_currentModeLabel)
    } }

    func exitZhuyinMode() { sync {
        _exitZhuyinModeImpl()
    } }

    private func _exitZhuyinModeImpl() {
        guard _isZhuyinMode else { return }
        _isZhuyinMode = false
        _clearZhuyinSlots(); _currentCandidates = []; _notifyCandidates()
        delegate?.engineDidShowToast(_currentModeLabel)
    }

    // MARK: - Pinyin lookup

    func exitPinyinMode() { sync {
        _isPinyinMode = false; _pinyinBuffer = ""
        _currentCandidates = []; _notifyCandidates()
        delegate?.engineDidClearComposing()
    } }

    func handlePinyinLetter(_ ch: String) { sync {
        guard _isPinyinMode else { return }
        _pinyinBuffer += ch
        _composing = _pinyinBuffer
        _notifyComposing()
    } }

    func handlePinyinTone(_ tone: Int) { sync {
        guard _isPinyinMode, !_pinyinBuffer.isEmpty else { return }
        let pinyin = _pinyinBuffer + "\(tone)"
        let chars = zhuyinLookup.charsForPinyin(pinyin)
        guard !chars.isEmpty else { return }
        let display: [String]
        if _pinyinSimplified {
            let t2s = cinTable.t2s
            var seen = Set<String>()
            display = chars.compactMap { c in
                let s = t2s[c] ?? c; return seen.insert(s).inserted ? s : nil
            }
        } else { display = chars }
        _currentCandidates = display.map { c in
            let codes = cinTable.reverseLookup(c)
            return codes.isEmpty ? c : "\(c) \(codes.joined(separator: "/"))"
        }
        _composing = pinyin; _notifyComposing(); _notifyCandidates()
    } }

    func handlePinyinSpace() { sync {
        guard _isPinyinMode else { return }
        if !_pinyinBuffer.isEmpty { _handlePinyinToneImpl(1) }
    } }

    func handlePinyinBackspace() { sync {
        guard _isPinyinMode else { return }
        if !_currentCandidates.isEmpty {
            _currentCandidates = []; _notifyCandidates()
            _composing = _pinyinBuffer; _notifyComposing()
        } else if !_pinyinBuffer.isEmpty {
            _pinyinBuffer = String(_pinyinBuffer.dropLast())
            _composing = _pinyinBuffer; _notifyComposing()
            if _pinyinBuffer.isEmpty { delegate?.engineDidClearComposing() }
        }
    } }

    func handlePinyinEscape() { sync {
        guard _isPinyinMode else { return }
        if !_pinyinBuffer.isEmpty || !_currentCandidates.isEmpty {
            _pinyinBuffer = ""; _currentCandidates = []; _notifyCandidates()
            delegate?.engineDidClearComposing()
        } else {
            _isPinyinMode = false; _pinyinBuffer = ""
            _currentCandidates = []; _notifyCandidates()
            delegate?.engineDidClearComposing()
            delegate?.engineDidShowToast(_currentModeLabel)
        }
    } }

    func selectPinyinCandidate(at index: Int) { sync {
        guard _isPinyinMode, index < _currentCandidates.count else { return }
        let entry = _currentCandidates[index]
        let char = String(entry.prefix(1))
        delegate?.engineDidCommit(char)
        let codes = cinTable.reverseLookup(char)
        if !codes.isEmpty { delegate?.engineDidShowToast("\(char) → \(codes.joined(separator: " / "))") }
        _pinyinBuffer = ""; _currentCandidates = []; _notifyCandidates()
        delegate?.engineDidClearComposing()
    } }

    // MARK: - Zhuyin

    private static let zyInitials: Set<String> = [
        "ㄅ","ㄆ","ㄇ","ㄈ","ㄉ","ㄊ","ㄋ","ㄌ",
        "ㄍ","ㄎ","ㄏ","ㄐ","ㄑ","ㄒ","ㄓ","ㄔ","ㄕ","ㄖ","ㄗ","ㄘ","ㄙ",
    ]
    private static let zyMedials: Set<String> = ["ㄧ","ㄨ","ㄩ"]
    private static let zyFinals: Set<String> = [
        "ㄚ","ㄛ","ㄜ","ㄝ","ㄞ","ㄟ","ㄠ","ㄡ","ㄢ","ㄣ","ㄤ","ㄥ","ㄦ",
    ]

    func handleZhuyinSymbol(_ zy: String) { sync {
        if Self.zyInitials.contains(zy) { _zyInitial = zy }
        else if Self.zyMedials.contains(zy) { _zyMedial = zy }
        else if Self.zyFinals.contains(zy) { _zyFinal = zy }
        _zhuyinBuffer = _zyInitial + _zyMedial + _zyFinal
        delegate?.engineDidUpdateComposing(_zhuyinBuffer)
    } }

    func handleZhuyinTone(_ tone: String) { sync {
        guard !_zhuyinBuffer.isEmpty else { return }
        let zhuyin = tone == "˙" ? "˙" + _zhuyinBuffer : _zhuyinBuffer + tone
        _zhuyinLookup(zhuyin)
    } }

    func handleZhuyinSpace() { sync {
        guard !_zhuyinBuffer.isEmpty else { return }
        _zhuyinLookup(_zhuyinBuffer)  // tone 1
    } }

    private func _zhuyinLookup(_ zhuyin: String) {
        let raw = zhuyinLookup.charsForZhuyin(zhuyin)
        guard !raw.isEmpty else { return }
        let chars = zhuyinLookup.sortByFreq(raw, prevChar: _prevCommitted, curZhuyin: zhuyin)
        _currentCandidates = chars.map { char in
            let codes = cinTable.reverseLookup(char)
            return codes.isEmpty ? char : "\(char) \(codes.joined(separator: "/"))"
        }
        delegate?.engineDidUpdateComposing(zhuyin)
        _notifyCandidates()
    }

    private func _clearZhuyinSlots() {
        _zyInitial = ""; _zyMedial = ""; _zyFinal = ""; _zhuyinBuffer = ""
    }

    private func _backspaceZhuyin() {
        if !_zyFinal.isEmpty { _zyFinal = "" }
        else if !_zyMedial.isEmpty { _zyMedial = "" }
        else { _zyInitial = "" }
        _zhuyinBuffer = _zyInitial + _zyMedial + _zyFinal
    }

    // MARK: - Same-Sound

    private func _handleSameSound() {
        let results = zhuyinLookup.lookup(_sameSoundBase)
        DebugLog.log("YabomishKB: handleSameSound base=\(_sameSoundBase) results=\(results.count)")
        guard let first = results.first else { _resetComposing(); return }
        _currentCandidates = zhuyinLookup.sortByFreq(first.chars)
        _composing = _sameSoundBase
        delegate?.engineDidUpdateComposing("\(_sameSoundBase)[\(first.zhuyin)]")
        _notifyCandidates()
    }

    // MARK: - ,, Command

    private func _dispatchCommaCommand() {
        let cmd = _commaCommandBuffer.lowercased()
        _isInCommaCommand = false; _commaCommandBuffer = ""
        _resetComposing()

        let modeMap: [String: InputMode] = [
            "t": .t, "s": .s, "sp": .sp, "sl": .sl, "ts": .ts, "st": .st, "j": .j
        ]
        if cmd == "rs" { freqTracker.reset(); delegate?.engineDidShowToast("字頻已重置"); return }
        if cmd == "rl" { cinTable.reload(); delegate?.engineDidShowToast("字表已重載"); return }
        if cmd == "c" { delegate?.engineDidShowToast(_currentModeLabel); return }
        if cmd == "zh" {
            _isZhuyinMode.toggle()
            if _isZhuyinMode {
                _isSameSoundMode = false; _sameSoundBase = ""
                _isPinyinMode = false; _pinyinBuffer = ""
            }
            delegate?.engineDidShowToast(_isZhuyinMode ? "注" : _currentModeLabel)
            if !_isZhuyinMode { _clearZhuyinSlots(); _currentCandidates = []; _notifyCandidates() }
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
            let entering = !_isPinyinMode || (cmd == "pys") != _pinyinSimplified
            if entering {
                _isPinyinMode = true; _pinyinSimplified = (cmd == "pys")
                _isZhuyinMode = false; _clearZhuyinSlots()
                _isSameSoundMode = false; _sameSoundBase = ""
                _pinyinBuffer = ""; _currentCandidates = []; _notifyCandidates()
                delegate?.engineDidShowToast(cmd == "pys" ? "拼簡" : "拼繁")
            } else {
                _isPinyinMode = false; _pinyinBuffer = ""
                _currentCandidates = []; _notifyCandidates()
                delegate?.engineDidClearComposing()
                delegate?.engineDidShowToast(_currentModeLabel)
            }
            return
        }
        if cmd == "to" {
            _isSameSoundMode.toggle()
            if _isSameSoundMode {
                _isZhuyinMode = false; _clearZhuyinSlots()
                _isPinyinMode = false; _pinyinBuffer = ""
                _sameSoundBase = ""; _composing = ""
                delegate?.engineDidClearComposing()
                delegate?.engineDidShowToast("同音字模式：打碼送字後列同音字")
            } else {
                _sameSoundBase = ""; _composing = ""
                delegate?.engineDidClearComposing()
                _currentCandidates = []; _notifyCandidates()
                delegate?.engineDidShowToast(_currentModeLabel)
            }
            return
        }
        guard let mode = modeMap[cmd] else {
            delegate?.engineDidShowToast("未知命令 ,,\(cmd.uppercased())"); return
        }
        _inputMode = mode
        delegate?.engineDidShowToast(Self.modeLabels[mode] ?? "繁中")
    }

    /// Switch to a named mode (used by space-swipe cycle). Returns the display label.
    @discardableResult
    func switchToMode(_ name: String) -> String { sync {
        let modeMap: [String: InputMode] = [
            "t": .t, "s": .s, "sp": .sp, "sl": .sl, "ts": .ts, "st": .st, "j": .j
        ]
        if name == "zh" {
            if !_isZhuyinMode { _isZhuyinMode = true; _clearZhuyinSlots() }
            _isSameSoundMode = false; _sameSoundBase = ""; _composing = ""
            delegate?.engineDidShowToast("注")
            return "注"
        }
        if name == "to" {
            if !_isSameSoundMode {
                _isSameSoundMode = true; _sameSoundBase = ""; _composing = ""
                delegate?.engineDidClearComposing()
            }
            if _isZhuyinMode { _exitZhuyinModeImpl() }
            delegate?.engineDidShowToast("同音字模式")
            return "同"
        }
        // Regular input mode
        if _isZhuyinMode { _isZhuyinMode = false; _clearZhuyinSlots(); _currentCandidates = []; _notifyCandidates() }
        if _isSameSoundMode { _isSameSoundMode = false; _sameSoundBase = ""; _composing = "" }
        if let mode = modeMap[name] {
            _inputMode = mode
            let label = Self.modeLabels[mode] ?? "繁中"
            delegate?.engineDidShowToast(label)
            return label
        }
        return ""
    } }

    // MARK: - Internal impl (called from within queue, no locking)

    private func _handleBackspaceImpl() {
        if _isInCommaCommand {
            if _commaCommandBuffer.isEmpty {
                _isInCommaCommand = false; _composing = ","
                _notifyComposing()
            } else {
                _commaCommandBuffer = String(_commaCommandBuffer.dropLast())
                _composing = ",," + _commaCommandBuffer; _notifyComposing()
            }
            return
        }
        if _isZhuyinMode {
            if _currentCandidates.isEmpty && !_zhuyinBuffer.isEmpty {
                _backspaceZhuyin()
                if _zhuyinBuffer.isEmpty { delegate?.engineDidClearComposing() }
                else { delegate?.engineDidUpdateComposing(_zhuyinBuffer) }
            } else if !_currentCandidates.isEmpty {
                _currentCandidates = []; _notifyCandidates()
                delegate?.engineDidUpdateComposing(_zhuyinBuffer)
            }
            return
        }
        if _composing.isEmpty { return }
        _composing = String(_composing.dropLast())
        if _composing.isEmpty { _resetComposing() }
        else {
            _isWildcard = _composing.contains("*")
            _refreshCandidates(); _notifyComposing(); _notifyCandidates()
        }
    }

    private func _selectCandidateImpl(at index: Int) {
        DebugLog.log("YabomishKB: selectCandidate idx=\(index) count=\(_currentCandidates.count) composing='\(_composing)' zhuyin=\(_isZhuyinMode ? 1 : 0)")
        guard index < _currentCandidates.count else { return }
        if _isZhuyinMode {
            let full = _currentCandidates[index]
            let char = String(full.prefix(1))
            let codes = cinTable.reverseLookup(char)
            _commitText(char)
            if !codes.isEmpty { delegate?.engineDidShowToast("\(char) → \(codes.joined(separator: " / "))") }
            _clearZhuyinSlots(); _currentCandidates = []; _notifyCandidates()
            _exitZhuyinModeImpl()
        } else if _composing.isEmpty {
            _commitText(_currentCandidates[index])
        } else {
            _commitText(_currentCandidates[index])
        }
    }

    private func _handlePinyinToneImpl(_ tone: Int) {
        guard _isPinyinMode, !_pinyinBuffer.isEmpty else { return }
        let pinyin = _pinyinBuffer + "\(tone)"
        let chars = zhuyinLookup.charsForPinyin(pinyin)
        guard !chars.isEmpty else { return }
        let display: [String]
        if _pinyinSimplified {
            let t2s = cinTable.t2s
            var seen = Set<String>()
            display = chars.compactMap { c in
                let s = t2s[c] ?? c; return seen.insert(s).inserted ? s : nil
            }
        } else { display = chars }
        _currentCandidates = display.map { c in
            let codes = cinTable.reverseLookup(c)
            return codes.isEmpty ? c : "\(c) \(codes.joined(separator: "/"))"
        }
        _composing = pinyin; _notifyComposing(); _notifyCandidates()
    }

    // MARK: - Internal

    private func _canExtendCode(_ code: String) -> Bool {
        !cinTable.validNextKeys(after: code).isEmpty
    }

    public func validNextKeys() -> Set<Character> {
        sync {
            guard !_composing.isEmpty else { return [] }
            return cinTable.validNextKeys(after: _composing)
        }
    }

    private func _refreshCandidates() {
        let code = _composing
        if _inputMode == .j {
            _currentCandidates = cinTable.lookup(code + ",") + cinTable.lookup(code + ".")
            return
        }
        let raw = _isWildcard ? cinTable.wildcardLookup(code) : cinTable.lookup(code)
        _currentCandidates = ranker.rank(raw: raw, code: code, prev: _lastCommitted,
                                         mode: _inputMode, cinTable: cinTable, freqTracker: freqTracker)

        // Fuzzy match: if no candidates, try adjacent-key substitution
        if _currentCandidates.isEmpty && !_isWildcard && code.count >= 2 && prefs.fuzzyMatch {
            _currentCandidates = ranker.fuzzyLookup(code, cinTable: cinTable)
        }
    }

    private static let punctuationPairs: [String: String] = [
        "「": "」", "（": "）", "『": "』", "【": "】", "《": "》", "〈": "〉",
    ]

    private func _commitText(_ text: String) {
        DebugLog.log("YabomishKB: commitText='\(text)' composing='\(_composing)' sameSound=\(_isSameSoundMode ? 1 : 0)")
        // Same-sound step 1 → step 2
        if _isSameSoundMode && _sameSoundBase.isEmpty && text.count == 1 {
            let results = zhuyinLookup.lookup(text)
            DebugLog.log("YabomishKB: sameSound lookup char=\(text) results=\(results.count)")
            if !results.isEmpty {
                _sameSoundBase = text
                DebugLog.log("YabomishKB: sameSound base=\(text) zhuyin=\(results.first?.zhuyin ?? "?") chars=\(results.first?.chars.count ?? 0)")
                _handleSameSound(); return
            }
        }

        // Punctuation pairing: iOS default on, macOS default off
        if prefs.punctuationPairing, text.count == 1, let right = Self.punctuationPairs[text] {
            delegate?.engineDidCommitPair(text, right)
        } else {
            delegate?.engineDidCommit(text)
        }
        if !_composing.isEmpty && !_isSameSoundMode {
            freqTracker.record(code: _composing, char: text)
            freqTracker.recordBigram(prev: _lastCommitted, char: text)
            if !_prevCommitted.isEmpty {
                freqTracker.recordTrigram(prev2: _prevCommitted, prev1: _lastCommitted, char: text)
            }
            freqTracker.saveIfNeeded()
        }
        // Domain context tracking
        ranker.updateDomainContext(text)

        _prevCommitted = _lastCommitted
        _lastCommitted = text.count == 1 ? text : String(text.suffix(1))

        // Track recent committed text (for trigram + NER)
        _recentCommitted += text
        if _recentCommitted.count > 10 { _recentCommitted = String(_recentCommitted.suffix(10)) }
        let sentenceEnders: Set<Character> = ["。", "！", "？", ".", "!", "?", "\n", "；", ";"]
        if let last = text.last, sentenceEnders.contains(last) { _recentCommitted = "" }

        _composing = ""; _currentCandidates = []
        _isWildcard = false
        if _isSameSoundMode {
            // Stay in same-sound mode — reset for next character
            _sameSoundBase = ""; _composing = ""
            delegate?.engineDidClearComposing()
        } else {
            _sameSoundBase = ""
        }
        _notifyCandidates()

        if text.count == 1 && prefs.showCodeHint && MemoryBudget.canAfford(MemoryBudget.reverseTable) {
            let codes = cinTable.reverseLookup(text)
            if !codes.isEmpty { delegate?.engineDidShowToast("\(text) → \(codes.joined(separator: " / "))") }
        }

        // 聯想
        if prefs.suggestEnabled && !_isSameSoundMode && !_isZhuyinMode {
            let results = suggestionEngine.suggest(recentCommitted: _recentCommitted, lastText: text)
            if !results.isEmpty {
                delegate?.engineDidSuggest(results)
            }
        }
    }

    private func _resetComposing() {
        _composing = ""; _currentCandidates = []; _isWildcard = false
        _sameSoundBase = ""; _eatNextSpace = false
        _isInCommaCommand = false; _commaCommandBuffer = ""
        _clearZhuyinSlots()
        delegate?.engineDidClearComposing()
        _notifyCandidates()
    }

    /// Returns the shortest code hint for a candidate, or nil if it equals the current composing.
    func shortestCodeHint(for char: String) -> String? { sync {
        guard let codes = cinTable.shortestCodesTable[char] else { return nil }
        guard let best = codes.min(by: { $0.count < $1.count }) ?? codes.first else { return nil }
        return best.count < _composing.count ? best : nil
    } }

    private func _notifyComposing() { delegate?.engineDidUpdateComposing(_composing) }
    private func _notifyCandidates() { delegate?.engineDidUpdateCandidates(_currentCandidates) }
}
