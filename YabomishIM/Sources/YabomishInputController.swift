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

/// 拇指提示手別分類（QWERTY 硬體 keyCode，不依賴 layout）：
/// 左手 qwert/asdfg/zxcvb → 右手拇指按 Space；右手 yuiop/hjkl/nm → 左手拇指按 Space。
private let leftHandKeyCodes: Set<UInt16> = [12, 13, 14, 15, 17, 0, 1, 2, 3, 5, 6, 7, 8, 9, 11]
private let rightHandKeyCodes: Set<UInt16> = [16, 32, 34, 31, 35, 4, 38, 40, 45, 46, 37]

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
        // macOS Secure Event Input（密碼欄／Keychain 提示等）：
        // 預設放行不處理（密碼原樣送達，IM 完全不接觸）；使用者於偏好
        // 開放 allowSecureInput 時照常組字——但即使放行，安全期間
        // debug.log 與字頻學習一律靜音，不落檔不留學習記錄。
        let secure = IsSecureEventInputEnabled()
        DebugLog.muted = secure
        Self.freqTracker.suppressRecording = secure
        if secure {
            if !YabomishPrefs.allowSecureInput {
                if !engine.composing.isEmpty { engine.handleEscape() }
                panel.hide()
                if !Self.didNotifySecureInput {
                    Self.didNotifySecureInput = true
                    showModeToast("密碼欄位：輸入法暫停（可在設定開放）")
                }
                return false
            }
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

    /// 依偏好組合 toast 字體：system／rounded（SF Rounded）／serif（宋體系）／heiti（黑體系）
    private func toastLabelFont(size: CGFloat) -> NSFont {
        switch YabomishPrefs.toastFontStyle {
        case "rounded":
            if let desc = NSFont.systemFont(ofSize: size, weight: .semibold).fontDescriptor.withDesign(.rounded),
               let f = NSFont(descriptor: desc, size: size) { return f }
            return .systemFont(ofSize: size, weight: .semibold)
        case "serif":
            // 名稱是「Songti TC」（空格）；「Songti-TC」在系統上不存在會靜默回退
            return NSFont(name: "Songti TC", size: size) ?? .systemFont(ofSize: size, weight: .medium)
        case "heiti":
            return NSFont(name: "PingFang TC", size: size)
                ?? NSFont(name: "Heiti TC", size: size)
                ?? .systemFont(ofSize: size, weight: .medium)
        default:
            return .systemFont(ofSize: size, weight: .medium)
        }
    }

    /// #RRGGBB → NSColor（解析失敗回 fallback）；實作與候選窗共用 TextStyle
    private static func hexColor(_ hex: String, fallback: NSColor) -> NSColor {
        TextStyle.color(hex, fallback: fallback)
    }

    /// 建立並顯示 HUD 提示：先收起同槽位舊窗，淡出後僅在仍是同窗時清空槽位。
    private func showToast(_ text: String, style: ToastStyle, duration: Double, slot: ToastSlot) {
        Self.toastPanel(for: slot)?.orderOut(nil)
        guard let screen = NSScreen.main else { return }
        let label = NSTextField(labelWithString: text)
        label.font = style.font
        let fill = Self.hexColor(YabomishPrefs.toastTextColor, fallback: .white)
        if YabomishPrefs.toastStroke {
            // 字幕式描邊：strokeWidth 負值＝填色＋外框並存
            label.attributedStringValue = NSAttributedString(string: text, attributes: [
                .font: style.font,
                .foregroundColor: fill,
                .strokeColor: Self.hexColor(YabomishPrefs.toastStrokeColor, fallback: .black),
                .strokeWidth: TextStyle.strokePercent(px: YabomishPrefs.toastStrokeWidth,
                                                      fontSize: style.font.pointSize),
            ])
        } else {
            label.textColor = fill
        }
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
        win.alphaValue = YabomishPrefs.toastOpacity
        win.appearance = YabomishPrefs.resolvedAppearance
        label.frame = NSRect(x: 0, y: style.labelYOffset, width: rect.width, height: label.frame.height)
        let effects = YabomishPrefs.visualEffects
        if effects == "none" {
            // 無視覺效果：純色不透明底，無材質無玻璃
            let bg = FlatBackdropView(frame: NSRect(origin: .zero, size: rect.size))
            bg.radius = style.cornerRadius
            bg.addSubview(label)
            win.contentView = bg
        } else if effects == "full", #available(macOS 26.0, *) {
            // 完整效果：Liquid Glass——邊緣折射＋果凍質感
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: rect.size))
            glass.cornerRadius = style.cornerRadius
            let container = NSView(frame: NSRect(origin: .zero, size: rect.size))
            container.addSubview(label)
            glass.contentView = container
            win.contentView = glass
        } else {
            // 舊系統回落：hudWindow 毛玻璃
            let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: rect.size))
            bg.material = .hudWindow; bg.state = .active; bg.wantsLayer = true; bg.layer?.cornerRadius = style.cornerRadius
            bg.addSubview(label)
            win.contentView = bg
        }
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
            font: toastLabelFont(size: YabomishPrefs.toastFontSize),
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
        // 依 bundle ID 選偏好程式：dev 變體開 ~/Applications/YabomishDevPrefs.app
        //（寫 dev suite），stable 開 /Applications/YabomishPrefs.app。
        // 寫錯 suite 的話 IM 的偏好快照永遠看不到（這就是「調了沒反應」）。
        let isDev = (Bundle.main.bundleIdentifier ?? "").contains("Dev")
        let appPath = isDev
            ? NSHomeDirectory() + "/Applications/YabomishDevPrefs.app"
            : "/Applications/YabomishPrefs.app"
        guard FileManager.default.fileExists(atPath: appPath) else {
            let a = NSAlert()
            a.messageText = "找不到設定程式"
            a.informativeText = "請執行 yabomish.sh 安裝 \((appPath as NSString).lastPathComponent)。"
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

    /// engine `,,P` → 與選單「偏好設定⋯」共用 openPrefs() 的 dev/stable 判斷。
    func engineDidOpenPrefs() { openPrefs() }

    /// InputModeID（同時是該 mode 的 TISInputSourceID），與
    /// Info.plist 的 ComponentInputModeDict/tsInputModeListKey 對應；
    /// 切換透過 kTextServiceInputModePropertyTag，menu bar 圖示隨之更新。
    private static let inputModeIDChinese = Bundle.main.bundleIdentifier ?? "com.yabomishim.inputmethod.YabomishIM"
    private static let inputModeIDEnglish = (Bundle.main.bundleIdentifier ?? "com.yabomishim.inputmethod.YabomishIM") + ".English"

    /// 依引擎目前的中/英狀態設定系統 input mode（顯示在右上角圖示）。
    /// engine 是 per-client（controller 實例），此 property 亦 per-client。
    private func applyInputModeIcon(client: NSObjectProtocol & IMKTextInput) {
        let modeID = engine.isEnglishMode ? Self.inputModeIDEnglish : Self.inputModeIDChinese
        DebugLog.log("YabomishIM: applyInputModeIcon -> \(modeID) client=\(type(of: client))")
        super.setValue(modeID, forTag: kTextServiceInputModePropertyTag, client: client)
        DebugLog.log("YabomishIM: applyInputModeIcon done")
    }

    private static var lastAppliedKeyboardLayout: String?

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        _ = Self.inputSourceObserver
        let targetLayout = "com.apple.keylayout.ABC"
        if let client = sender as? (NSObjectProtocol & IMKTextInput) {
            client.overrideKeyboard(withKeyboardNamed: targetLayout)
            applyInputModeIcon(client: client)
            // 啟用當下呼叫 overrideKeyboard 經常被 IMK 忽略（尤其 Globe/Fn 切過來）；
            // 延遲重送一次，確保鍵盤佈局真的換成 ABC 而非沿用前一個來源（如 AZERTY）。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak client] in
                client?.overrideKeyboard(withKeyboardNamed: targetLayout)
            }
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
            if self.engine.isEnglishMode, !self.engCandidates.isEmpty,
               let client = self.engineClient ?? self.client() {
                self.selectEnglishCandidate(text, client: client)
                return
            }
            let idx = self.candidateIndex(of: text)
            self.engine.selectCandidate(at: idx)
        }
        // Reset engine state for new session
        engine.handleEscape()
        engine.clearCandidates()
        resetEnglishSuggestState()
        // 語境列握手（Prefs app → IM）：ContextBar 套用語境時先寫暫態鍵
        // "pendingInputMode" 再廣播 prefsChanged，refreshSnapshot() 已把該鍵
        // 讀走（讀後即移除）；於此消費（讀後即清），比照 ,,X<code> 套用輸入模式。
        // 點語境 chip 必先使 Prefs app 取得焦點（本 session 已 deactivate），
        // 故暫態值的消費點即下次 activateServer。
        if let mode = YabomishPrefs.pendingInputMode {
            YabomishPrefs.pendingInputMode = nil
            engine.switchToMode(mode)
        }
        if fromOtherIM && YabomishPrefs.showActivateToast {
            showModeToast(engine.currentModeLabel)
        }
        if CINImportCoordinator.showFirstUseTip {
            CINImportCoordinator.showFirstUseTip = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.showModeToast("空白鍵送字 ｜ \(self?.toggleKeyDisplay ?? "Shift") 切英文 ｜ ,,H 說明")
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

    /// 使用者在輸入法選單直接點選 mode（Yabomish / English）時同步引擎狀態；
    /// applyInputModeIcon 走 super，不會回到這裡。
    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        if tag == kTextServiceInputModePropertyTag {
            DebugLog.log("YabomishIM: setValue inputMode <- \(String(describing: value))")
            if let modeID = value as? String {
                resetEnglishSuggest(client: sender as? (NSObjectProtocol & IMKTextInput))
                engine.setEnglishMode(modeID == Self.inputModeIDEnglish)
            }
        }
        super.setValue(value, forTag: tag, client: sender)
    }

    /// 收編期間旗標：exitZhuyin/exitPinyinMode、handleEscape 會經 delegate 觸發
    /// engineDidShowToast，而此時 IM 已停用、焦點常已移到新 app，toast 會彈在
    /// 錯的畫面上；收編期間於 engineDidShowToast 靜音。
    private var isDeactivating = false

    override func deactivateServer(_ sender: Any!) {
        isDeactivating = true
        defer { isDeactivating = false }
        guard Self.activeSession === self else {
            // 過期 session：共享面板與 activeSession 一概不碰（引擎狀態由
            // 下次 activateServer 重置），但仍要清掉自己 client 殘留的組字
            // 底線，否則原 app 畫面留著未確認的底線組字。
            if let client = sender as? (NSObjectProtocol & IMKTextInput),
               !engine.composing.isEmpty || !engPrefix.isEmpty {
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            }
            resetEnglishSuggestState()
            super.deactivateServer(sender)
            return
        }
        if let client = sender as? (NSObjectProtocol & IMKTextInput) {
            if engine.isZhuyinMode || engine.isPinyinMode {
                if engine.isZhuyinMode { engine.exitZhuyinMode() }
                if engine.isPinyinMode { engine.exitPinyinMode() }
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            } else if !engine.composing.isEmpty || !engPrefix.isEmpty {
                // 切換視窗／輸入法時丟棄組字（多數 IM 慣例：未確認的字不代送）。
                // 舊行為有候選時以空白鍵代送第一候選，使用者切個視窗字就憑空落底文。
                engine.handleEscape()
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            }
        }
        llmGeneration += 1   // 切 app → 丟棄進行中的 LLM 結果
        resetEnglishSuggestState()
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

    /// 最後一碼的左右手別（拇指提示用）；非字母鍵或 pref 關閉時為 nil。
    /// 候選窗 show 時才把 side 餵給 CandidatePanel.thumbHintSide。
    private static var _lastKeyHandKey = 0
    private var lastKeyHand: CandidatePanel.ThumbSide? {
        get { (objc_getAssociatedObject(self, &Self._lastKeyHandKey) as? AssocThumbSide)?.v }
        set { objc_setAssociatedObject(self, &Self._lastKeyHandKey, newValue.map { AssocThumbSide($0) }, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    private final class AssocThumbSide {
        let v: CandidatePanel.ThumbSide
        init(_ v: CandidatePanel.ThumbSide) { self.v = v }
    }

    func handleWithNewEngine(_ event: NSEvent, client: NSObjectProtocol & IMKTextInput) -> Bool {
        engineClient = client

        if event.type == .flagsChanged {
            DebugLog.log("YabomishIM: flagsChanged key=\(event.keyCode) shift=\(event.modifierFlags.contains(.shift)) caps=\(event.modifierFlags.contains(.capsLock)) lastDown=\(newEngineLastShiftDown)")
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
            // capsLockToggles 時 .capsLock flag 是切換鍵的殘留狀態、無大寫語意，遮罩為 false
            let wantShift = flags.contains(.shift) != (capsLockToggles ? false : flags.contains(.capsLock))
            // 英文字典聯想（iOS 版移植）：字母攔截成 marked 組字、候選窗顯示補全；
            // 安全輸入期間不聯想——密碼不進字典/trie 比對（與 iOS inPasswordField 一致）
            if YabomishPrefs.englishSuggest, !IsSecureEventInputEnabled() {
                return handleEnglishSuggest(keyCode: keyCode, wantShift: wantShift, client: client)
            }
            if !engPrefix.isEmpty { resetEnglishSuggest(client: client) }
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
                let s = (!capsLockToggles && flags.contains(.capsLock)) ? String(ch).uppercased() : String(ch)
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
            lastKeyHand = leftHandKeyCodes.contains(keyCode) ? .right
                        : rightHandKeyCodes.contains(keyCode) ? .left : nil
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

    // MARK: - 英文字典聯想（移植自 yabomish iOS 版）

    /// 英文聯想狀態盒：extension 不能存儲存屬性，比照 engine 用 associated object。
    private final class EnglishSuggestState {
        var prefix = ""               // marked 組字中的前綴（保留實際大小寫）
        var candidates: [String] = [] // 目前面板上的候選快照
        lazy var userDict = UserEnglishDict(dir: AppConstants.sharedDir)
    }
    private static var _engStateKey = 0
    private var engState: EnglishSuggestState {
        if let s = objc_getAssociatedObject(self, &Self._engStateKey) as? EnglishSuggestState { return s }
        let s = EnglishSuggestState()
        objc_setAssociatedObject(self, &Self._engStateKey, s, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return s
    }
    private var engPrefix: String {
        get { engState.prefix }
        set { engState.prefix = newValue }
    }
    private var engCandidates: [String] {
        get { engState.candidates }
        set { engState.candidates = newValue }
    }
    private var engUserDict: UserEnglishDict { engState.userDict }
    private static let englishSelKeys: [Character] = Array("123456789")

    /// 英文模式＋聯想開啟時的按鍵路徑：字母累積為 marked 組字、數字鍵／
    /// 點選送詞、Escape 丟棄、其餘鍵先送出前綴再放行（行為同無聯想）。
    private func handleEnglishSuggest(keyCode: UInt16, wantShift: Bool,
                                      client: NSObjectProtocol & IMKTextInput) -> Bool {
        // marked 被外部收編（點選他處未走 deactivate）：前綴作廢重來
        if !engPrefix.isEmpty, client.markedRange().length != engPrefix.count {
            resetEnglishSuggestState()
        }
        if let ch = keyCodeToChar[keyCode], ch.isLetter {
            engPrefix.append(wantShift ? Character(ch.uppercased()) : ch)
            updateEnglishComposing(client: client)
            return true
        }
        if keyCode == 51 { // Backspace
            guard !engPrefix.isEmpty else { return false }
            engPrefix.removeLast()
            updateEnglishComposing(client: client)
            return true
        }
        if let digit = keyCodeToDigit[keyCode], !engCandidates.isEmpty,
           let word = panel.selectByKey(digit) {
            selectEnglishCandidate(word, client: client)
            return true
        }
        if keyCode == 53 { // Escape：丟棄組字不落底文
            guard !engPrefix.isEmpty else { return false }
            resetEnglishSuggest(client: client)
            return true
        }
        // 其餘鍵（空白／Enter／Tab／標點／方向）：先落前綴再放行原按鍵
        commitEnglishComposing(client: client)
        return false
    }

    /// 組字更新：marked 同步 + 候選重算（user dict 在前、字頻 trie 在後，同 iOS）。
    private func updateEnglishComposing(client: NSObjectProtocol & IMKTextInput) {
        if engPrefix.isEmpty {
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                 replacementRange: notFoundRange)
            engCandidates = []
            panel.hide()
            return
        }
        client.setMarkedText(engPrefix,
                             selectionRange: NSRange(location: engPrefix.count, length: 0),
                             replacementRange: notFoundRange)
        let lower = engPrefix.lowercased()
        var results: [String] = []
        if lower.count >= 2 {
            let trie = EnglishTrie.shared.search(prefix: lower, limit: 6).filter { $0 != lower }
            let user = engUserDict.search(prefix: lower, limit: 4)
                .filter { $0 != lower && !trie.contains($0) }
            results = user + trie
            if results.isEmpty && lower.count >= 3
                && EnglishTrie.shared.search(prefix: lower, limit: 1).first != lower
                && !engUserDict.contains(lower) {
                results.append("+\(lower)")
            }
        }
        engCandidates = results
        showEnglishPanel(client: client)
    }

    /// 送出前綴字面並清場（空白／Enter／標點等放行前呼叫）。
    private func commitEnglishComposing(client: NSObjectProtocol & IMKTextInput) {
        guard !engPrefix.isEmpty else { return }
        client.insertText(engPrefix, replacementRange: notFoundRange)
        resetEnglishSuggestState()
        panel.hide()
    }

    /// 選候選：insertText 會以送出的詞取代 marked 組字。
    private func selectEnglishCandidate(_ word: String, client: NSObjectProtocol & IMKTextInput) {
        var w = word
        var addToDict = false
        if w.hasPrefix("+") {
            // "+word" 虛候選：把生詞收進使用者字典再送出
            w = String(w.dropFirst())
            addToDict = true
        }
        // 大小寫跟隨已打前綴（字典內永遠存小寫；送出時才轉）
        let letters = engPrefix.filter(\.isLetter)
        if !letters.isEmpty, letters.allSatisfy(\.isUppercase), letters.count > 1 {
            w = w.uppercased()
        } else if engPrefix.first?.isUppercase == true {
            w = w.capitalized
        }
        if addToDict {
            engUserDict.add(w)
            showCodeHintToast("已加入字典：\(w.lowercased())")
        }
        client.insertText(w, replacementRange: notFoundRange)
        resetEnglishSuggestState()
        panel.hide()
    }

    /// 清 marked 與面板（Escape／模式切換／聯想關閉時的殘留收拾）。
    private func resetEnglishSuggest(client: (NSObjectProtocol & IMKTextInput)?) {
        if let client, !engPrefix.isEmpty {
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                 replacementRange: notFoundRange)
        }
        resetEnglishSuggestState()
        panel.hide()
    }

    private func resetEnglishSuggestState() {
        engPrefix = ""
        engCandidates = []
    }

    /// 英文候選面板：與中文候選共用游標定位／固定模式邏輯。
    private func showEnglishPanel(client: NSObjectProtocol & IMKTextInput) {
        guard !engCandidates.isEmpty else { panel.hide(); return }
        let cursorRect = Self.queryCursorRect(client: client,
                                              markedLength: max(0, client.markedRange().length))
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
        panel.thumbHintSide = nil   // 英文聯想非組字碼，不顯示拇指提示
        panel.show(candidates: engCandidates, selKeys: Self.englishSelKeys,
                   at: origin, composing: engPrefix, preselectFirst: false)
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

    /// 每行程只提示一次「密碼欄位暫停」toast（避免每個按鍵都彈窗）。
    private static var didNotifySecureInput = false

    private static var _shiftUsedKey = 0
    private var newEngineShiftUsed: Bool {
        get { (objc_getAssociatedObject(self, &Self._shiftUsedKey) as? NSNumber)?.boolValue ?? false }
        set { objc_setAssociatedObject(self, &Self._shiftUsedKey, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// 中英切換鍵（issue #18）：englishToggleKey ∈ {shift, capslock, both, none}。
    /// capslock/both → Caps Lock 變專用切換鍵，.capsLock flag 不再有「大寫」語意，
    /// 系統 caps 狀態/LED 是否翻轉皆不影響打字行為（由呼叫端遮罩）。
    /// capslock → Shift 快按不觸發切換，但 Shift 當修飾鍵（暫時英文/萬用碼/符號）照常用。
    /// none → 兩鍵皆不切（英文僅從輸入法選單選），.capsLock 恢復大寫語意。
    private var capsLockToggles: Bool {
        let k = YabomishPrefs.englishToggleKey
        return k == "capslock" || k == "both"
    }
    private var shiftToggles: Bool {
        let k = YabomishPrefs.englishToggleKey
        return k == "shift" || k == "both"
    }

    /// 切換鍵的顯示名（首次使用提示等文案用）。
    private var toggleKeyDisplay: String {
        switch YabomishPrefs.englishToggleKey {
        case "capslock": return "⇪"
        case "both": return "⇪/Shift"
        case "none": return "選單"
        default: return "Shift"
        }
    }

    private func toggleEnglishModeAndIcon() {
        if !engine.composing.isEmpty { engine.handleEscape() }
        resetEnglishSuggest(client: engineClient ?? client())
        engine.toggleEnglishMode()
        if let client = engineClient ?? client() {
            applyInputModeIcon(client: client)
        }
    }

    private func handleNewEngineFlagsChanged(_ event: NSEvent) -> Bool {
        // Caps Lock（keyCode 57，kVK_CapsLock）：每次實體按壓產生一個
        // flagsChanged，.capsLock flag 為 toggle 後的新狀態。
        // 消費事件無法阻止系統鎖定（狀態在派發前已翻轉），因此：
        //   IOHID 可用（正常）→ 只在 →ON 轉換觸發切換，切完 forceOff 把鎖定
        //     壓回 off；force-off 產生的 flag=false 回聲被同一閘門濾掉。
        //     若使用者在別處留下 latched ON，進來的第一下（→OFF）只清鎖不
        //     觸發——再按即正常。
        //   IOHID 不可用 → 退回每按壓切一次（無 force-off 就無回聲）；
        //     殘留狀態由 capsLockToggles 遮罩擋住打字行為。
        if capsLockToggles && event.keyCode == 57 {
            if CapsLockControl.available {
                if event.modifierFlags.contains(.capsLock) {
                    toggleEnglishModeAndIcon()
                    CapsLockControl.forceOff()
                }
            } else {
                toggleEnglishModeAndIcon()
            }
            return true
        }
        let shiftDown = event.modifierFlags.contains(.shift)
        guard shiftToggles else { return false }
        if shiftDown {
            newEngineLastShiftDown = event.timestamp
            newEngineShiftUsed = false
        } else if newEngineLastShiftDown > 0 {
            if event.timestamp - newEngineLastShiftDown < 0.3 && !newEngineShiftUsed {
                toggleEnglishModeAndIcon()
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
        // 收編期間（deactivateServer）退出模式流程會觸發 toast，此時焦點已
        // 不在原 client，靜音避免彈到別的 app 畫面上。
        guard !isDeactivating else { return }
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

    /// `,,AI` 裸指令：開獨立浮動輸入窗（nonactivating，client 焦點不動），
    /// 可打中文/空白/任意輸入法內容；Enter 送出 → engineDidRequestLLM。
    /// prefill 為 preset 樣板展開結果；{clip} 在這裡代換成剪貼簿全文。
    func engineDidOpenLLMPrompt(prefill: String) {
        let filled = prefill.replacingOccurrences(of: "{clip}",
                                                with: ClipboardProcessor.plainText() ?? "")
        LLMPromptPanel.shared.show(prefill: filled) { [weak self] prompt in
            self?.engineDidRequestLLM(prompt)
        }
    }

    /// `,,PR` 裸指令：開 preset 選擇器；選中後把樣板送進 LLM 輸入窗讓使用者修改。
    func engineDidOpenPresetPicker(_ items: [(key: String, name: String, prompt: String)]) {
        guard !items.isEmpty else {
            DebugLog.log("engineDidOpenPresetPicker: empty")
            engineDidShowToast("無 preset — 在 commands.json 加 type:preset")
            return
        }
        PresetPickerPanel.shared.show(items: items) { [weak self] prompt in
            self?.engineDidOpenLLMPrompt(prefill: prompt)
        }
    }


    // MARK: - ,,AI prompt mode

    /// 產生中的 fm 工作代次：切 app / deactivate / 新 prompt 會讓舊結果作廢。
    private static var _llmGenerationKey = 0
    private var llmGeneration: Int {
        get { (objc_getAssociatedObject(self, &Self._llmGenerationKey) as? Int) ?? 0 }
        set { objc_setAssociatedObject(self, &Self._llmGenerationKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// `,,AI<prompt>`：非同步呼叫 `aiCommand` 樣板（預設 /usr/bin/fm respond）。
    /// 完成時若當初觸發的 client 仍有效且代次未過期 → commit 到游標；
    /// 否則寫入剪貼簿 + toast。逾時 30 秒由 Process timeout 控制。
    func engineDidRequestLLM(_ prompt: String) {
        llmGeneration += 1
        let gen = llmGeneration
        let client = engineClient   // weak 參考先取強引用快照
        DebugLog.log("engineDidRequestLLM: gen=\(gen) prompt=\(prompt.prefix(40))")

        let clip = ClipboardProcessor.plainText() ?? ""   // NSPasteboard 要在 main thread 讀
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.runFM(prompt: prompt, clip: clip)
            DispatchQueue.main.async {
                guard let self = self, self.llmGeneration == gen else {
                    DebugLog.log("engineDidRequestLLM: stale gen dropped")
                    return
                }
                switch result {
                case .success(let text):
                    // 觸發時的 client 仍是當前 session 的 client 才直接上屏；
                    // 換欄位/換 app 後寫入舊 client 會插進錯的地方 → 改放剪貼簿。
                    if let client, self.engineClient === client {
                        let range = client.markedRange()
                        client.insertText(text, replacementRange: range)
                    } else {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        self.showModeToast("焦點已切換：LLM 結果已放入剪貼簿")
                    }
                case .failure(let msg):
                    self.showModeToast("LLM 失敗：\(msg)")
                }
            }
        }
    }

    private enum FMResult { case success(String), failure(String) }

    /// 同步執行 `aiCommand` 樣板（預設 `/usr/bin/fm respond {prompt}`），
    /// 回傳 stdout 或錯誤描述。在背景佇列呼叫。
    /// 樣板以空白切 argv：第一欄是可執行檔，{prompt} 佔位符整欄替換；
    /// {clip} 佔位符同理（呼叫端已在 main thread 取好的剪貼簿快照——
    /// NSPasteboard 在背景執行緒讀不保證安全）。沒寫 {prompt} 時 prompt 追加為最後一欄。
    /// args 內不支援引號跳脫（MVP）。
    /// ⚠️ 注意：{prompt}/{clip} 內容會進 argv — ps auxww 看得到，不適合放機密。
    private static func runFM(prompt: String, clip: String) -> FMResult {
        let tmpl = YabomishPrefs.aiCommand.trimmingCharacters(in: .whitespaces)
        var argv = tmpl.split(separator: " ").map {
            $0.replacingOccurrences(of: "{prompt}", with: prompt)
              .replacingOccurrences(of: "{clip}", with: clip)
        }
        if !tmpl.contains("{prompt}") { argv.append(prompt) }
        guard let exec = argv.first, !exec.isEmpty else {
            return .failure("aiCommand 為空")
        }
        let execURL: URL
        if exec.contains("/") {
            execURL = URL(fileURLWithPath: exec)
        } else {
            // 無路徑 → 走 PATH：/usr/bin/env 做 lookup，與使用者在 shell 打的行為一致
            execURL = URL(fileURLWithPath: "/usr/bin/env")
        }
        if exec.contains("/"), !FileManager.default.isExecutableFile(atPath: exec) {
            return .failure("\(exec) 不存在或不可執行")
        }
        let p = Process()
        p.executableURL = execURL
        p.arguments = exec.contains("/") ? Array(argv.dropFirst()) : argv
        let out = Pipe(); let err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run() } catch {
            return .failure("fm 啟動失敗：\(error.localizedDescription)")
        }
        // Watchdog：30 秒未完成即終止。fm 內部也有等待上限，雙保險。
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { p.terminate() }
        // 兩條 pipe 各開一條 drain 執行緒：先 waitUntilExit 再讀會在
        // 輸出 >64KB（pipe buffer）時 deadlock——child 卡在 write 永不 exit。
        var outData = Data(); var errData = Data()
        let drain = DispatchGroup()
        drain.enter()
        DispatchQueue.global().async {
            outData = out.fileHandleForReading.readDataToEndOfFile(); drain.leave()
        }
        drain.enter()
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile(); drain.leave()
        }
        p.waitUntilExit()
        drain.wait()
        let stdout = String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // 被 watchdog terminate → uncaughtSignal（SIGTERM）；視為逾時。
        if p.terminationReason == .uncaughtSignal { return .failure("逾時（30s）") }
        guard p.terminationStatus == 0 else {
            // fm 常見錯誤：license 未同意、模型未就緒、裝置不支援 → 把 stderr 給使用者
            let detail = stderr.isEmpty ? "exit \(p.terminationStatus)" : stderr
            return .failure(detail.count > 60 ? String(detail.prefix(60)) + "…" : detail)
        }
        guard !stdout.isEmpty else { return .failure("fm 無輸出") }
        return .success(stdout)
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
        // 拇指提示：左手碼 → .right（右下點）、右手碼 → .left（左下點）；
        // 僅組字中顯示，pref 關時 CandidatePanel 內部自己攔下。
        panel.thumbHintSide = lastKeyHand
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
