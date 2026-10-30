import Cocoa
import InputMethodKit

/// ,,LLM 獨立 prompt 輸入窗。
///
/// 為什麼是浮動窗而不是 inline 組字：inline 只能收 ASCII（CIN 碼會被引擎拆碼），
/// 使用者需要打中文 prompt；獨立 NSTextField 走 AppKit 正常事件路徑，
/// 可以直接用系統任何輸入法（含 Yabomish 自己）打字。
///
/// .nonactivatingPanel：我們是 LSUIElement 代理 app，若讓視窗 activate，
/// client app 會失去 key status、IMK 焦點跳走——所以維持 nonactivating，
/// 但覆寫 canBecomeKey 讓視窗可以吃鍵盤。Esc/失焦關閉，Enter 送出。
final class LLMPromptPanel: NSPanel, NSTextFieldDelegate {
    static let shared = LLMPromptPanel()

    private let field = NSTextField(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "💬 LLM")
    private let hintLabel = NSTextField(labelWithString: "Enter 送出 · Esc 取消")
    private var onSubmit: ((String) -> Void)?

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 116),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // 背景：HUD 材質，與固定候選窗同一個視覺語言
        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        bg.layer?.masksToBounds = true
        self.contentView = bg

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .right

        field.placeholderString = "輸入 prompt…（可用任何輸入法，含中文）"
        field.font = .systemFont(ofSize: 15)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.delegate = self
        field.lineBreakMode = .byTruncatingTail
        field.cell?.sendsActionOnEndEditing = false   // 只走 doCommandBy 明確分流

        bg.addSubview(titleLabel)
        bg.addSubview(hintLabel)
        bg.addSubview(field)
        for v in [titleLabel, hintLabel, field] { v.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: bg.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 16),
            hintLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -16),
            field.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            field.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -16),
            field.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -16),
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 顯示在滑鼠所在螢幕的上三分之一處（Spotlight 慣例）。
    /// onSubmit 只在 Enter 且有非空內容時觸發；Esc/失焦＝放棄不送。
    func show(onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
        field.stringValue = ""
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            let x = vf.midX - frame.width / 2
            let y = vf.minY + vf.height * 0.62
            setFrameTopLeftPoint(NSPoint(x: x, y: y))
        }
        self.appearance = YabomishPrefs.resolvedAppearance
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
    }

    func dismiss() {
        onSubmit = nil
        orderOut(nil)
    }

    // MARK: - NSTextFieldDelegate

    /// Enter/Esc 走 command 分流（sendsActionOnEndEditing = false，所以 field
    /// 的 action 不會先到）。Escape = cancelOperation。
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let cb = onSubmit
            dismiss()
            if !text.isEmpty { cb?(text) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
            return true
        default:
            return false
        }
    }

    /// 失焦（使用者點回 app）＝放棄，同 Spotlight/Alfred 慣例
    override func resignKey() {
        super.resignKey()
        if !isKeyWindow { dismiss() }
    }
}
