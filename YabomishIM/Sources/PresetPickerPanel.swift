import Cocoa

/// ,,PR preset 選擇器——小而快的浮動清單，不搶 client 焦點。
///
/// 鍵盤操作：↑↓ 移動、Enter 選取、數字鍵 1-9 直選、Esc 取消。
/// 與 LLMPromptPanel 同樣是 .nonactivatingPanel + canBecomeKey：
/// client app 保持 key status，IME 焦點不跳走，但視窗可以吃鍵盤。
final class PresetPickerPanel: NSPanel {
    static let shared = PresetPickerPanel()

    private struct Item {
        let key: String
        let name: String
        let prompt: String
    }

    private var items: [Item] = []
    private var selected = 0
    private var onPick: ((String) -> Void)?
    private var rowLabels: [NSTextField] = []
    private let stackView = NSStackView()

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 40),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 10
        bg.layer?.masksToBounds = true
        self.contentView = bg

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: bg.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 每列顯示 `[n] 名稱 — 樣板首行`，樣板首行讓使用者不看說明也知道選了什麼。
    func show(items: [(key: String, name: String, prompt: String)],
              onPick: @escaping (String) -> Void) {
        self.items = items.map { Item(key: $0.key, name: $0.name, prompt: $0.prompt) }
        self.onPick = onPick
        self.selected = 0
        rebuildRows()

        // 高度跟列數走（單列約 22pt）
        let h = 8 * 2 + CGFloat(items.count) * 22
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            let x = vf.midX - 180
            let y = vf.minY + vf.height * 0.62
            setFrame(NSRect(x: x, y: y - h, width: 360, height: h), display: true)
        }
        self.appearance = YabomishPrefs.resolvedAppearance
        makeKeyAndOrderFront(nil)
    }

    private func rebuildRows() {
        rowLabels.forEach { $0.removeFromSuperview() }
        rowLabels = items.enumerated().map { i, it in
            let firstLine = it.prompt.components(separatedBy: .newlines).first ?? it.prompt
            let preview = firstLine.count > 22 ? String(firstLine.prefix(22)) + "…" : firstLine
            let tf = NSTextField(labelWithString: "\(i + 1). \(it.name)  —  \(preview)")
            tf.font = .systemFont(ofSize: 13, weight: i == selected ? .semibold : .regular)
            tf.textColor = i == selected ? .controlAccentColor : .labelColor
            return tf
        }
        stackView.arrangedSubviews.forEach { stackView.removeArrangedSubview($0); $0.removeFromSuperview() }
        rowLabels.forEach { stackView.addArrangedSubview($0) }
    }

    private func pick(_ i: Int) {
        guard items.indices.contains(i) else { return }
        let prompt = items[i].prompt
        let cb = onPick          // 先留住 callback——dismiss() 會清 nil
        dismiss()
        cb?(prompt)
    }

    func dismiss() {
        onPick = nil
        orderOut(nil)
    }

    /// 非文字欄位：keyDown 自己接。數字鍵直選、方向鍵移動、Enter 確認、Esc 取消。
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            dismiss()
        case 36, 76: // Return / Enter
            pick(selected)
        case 126: // ↑
            selected = (selected - 1 + items.count) % max(items.count, 1)
            rebuildRows()
        case 125: // ↓
            selected = (selected + 1) % max(items.count, 1)
            rebuildRows()
        default:
            if let chars = event.characters, let digit = chars.first.flatMap({ Int(String($0)) }),
               (1...9).contains(digit) {
                pick(digit - 1)
            }
        }
    }

    /// 失焦＝取消（同 Spotlight 慣例）
    override func resignKey() {
        super.resignKey()
        if !isKeyWindow { dismiss() }
    }
}
