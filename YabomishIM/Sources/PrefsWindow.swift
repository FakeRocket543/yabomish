import Cocoa

final class PrefsWindow: NSPanel {
    static let shared = PrefsWindow()

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 340),
                   styleMask: [.titled, .closable, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        self.title = "Yabomish 偏好設定"
        self.level = .floating
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces]

        let bg = NSVisualEffectView()
        bg.material = .windowBackground
        bg.state = .active
        self.contentView = bg

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bg.topAnchor),
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bg.bottomAnchor),
        ])

        // — 選字窗模式 —
        let modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        modePopup.addItems(withTitles: ["游標跟隨", "固定位置"])
        modePopup.selectItem(at: YabomishPrefs.panelPosition == "fixed" ? 1 : 0)
        modePopup.target = self; modePopup.action = #selector(modeChanged(_:))
        stack.addArrangedSubview(row("選字窗模式", modePopup))

        // — 對齊 —
        let alignPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        alignPopup.addItems(withTitles: ["靠左", "置中", "靠右"])
        let alignIdx = ["left": 0, "center": 1, "right": 2][YabomishPrefs.fixedAlignment] ?? 1
        alignPopup.selectItem(at: alignIdx)
        alignPopup.target = self; alignPopup.action = #selector(alignChanged(_:))
        stack.addArrangedSubview(row("對齊（固定模式）", alignPopup))

        // — 透明度 —
        let alphaSlider = NSSlider(value: Double(YabomishPrefs.fixedAlpha), minValue: 0.3, maxValue: 1.0, target: self, action: #selector(alphaChanged(_:)))
        alphaSlider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        stack.addArrangedSubview(row("透明度", alphaSlider))

        // — 字體大小 —
        let fontStepper = NSStepper(frame: .zero)
        fontStepper.minValue = 12; fontStepper.maxValue = 28; fontStepper.increment = 1
        fontStepper.integerValue = Int(YabomishPrefs.fontSize)
        fontStepper.target = self; fontStepper.action = #selector(fontSizeChanged(_:))
        let fontLabel = NSTextField(labelWithString: "\(Int(YabomishPrefs.fontSize)) pt")
        fontLabel.tag = 100
        let fontRow = row("字體大小", hStack(fontLabel, fontStepper))
        stack.addArrangedSubview(fontRow)

        // — 固定模式字體大小 —
        let fixedFontStepper = NSStepper(frame: .zero)
        fixedFontStepper.minValue = 12; fixedFontStepper.maxValue = 32; fixedFontStepper.increment = 1
        fixedFontStepper.integerValue = Int(YabomishPrefs.fixedFontSize)
        fixedFontStepper.target = self; fixedFontStepper.action = #selector(fixedFontSizeChanged(_:))
        let fixedFontLabel = NSTextField(labelWithString: "\(Int(YabomishPrefs.fixedFontSize)) pt")
        fixedFontLabel.tag = 101
        stack.addArrangedSubview(row("固定模式字體", hStack(fixedFontLabel, fixedFontStepper)))

        // — Toast 大小 —
        let toastStepper = NSStepper(frame: .zero)
        toastStepper.minValue = 20; toastStepper.maxValue = 72; toastStepper.increment = 4
        toastStepper.integerValue = Int(YabomishPrefs.toastFontSize)
        toastStepper.target = self; toastStepper.action = #selector(toastSizeChanged(_:))
        let toastLabel = NSTextField(labelWithString: "\(Int(YabomishPrefs.toastFontSize)) pt")
        toastLabel.tag = 102
        stack.addArrangedSubview(row("模式提示大小", hStack(toastLabel, toastStepper)))

        // — 自動送字 —
        let autoBtn = NSButton(checkboxWithTitle: "滿碼自動送字", target: self, action: #selector(autoCommitChanged(_:)))
        autoBtn.state = YabomishPrefs.autoCommit ? .on : .off
        stack.addArrangedSubview(autoBtn)
    }

    override var canBecomeKey: Bool { true }

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        center()
        makeKeyAndOrderFront(nil)
    }

    // MARK: - Actions

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        YabomishPrefs.panelPosition = sender.indexOfSelectedItem == 1 ? "fixed" : "cursor"
    }

    @objc private func alignChanged(_ sender: NSPopUpButton) {
        let keys = ["left", "center", "right"]
        YabomishPrefs.fixedAlignment = keys[sender.indexOfSelectedItem]
    }

    @objc private func alphaChanged(_ sender: NSSlider) {
        YabomishPrefs.fixedAlpha = CGFloat(sender.doubleValue)
    }

    @objc private func fontSizeChanged(_ sender: NSStepper) {
        YabomishPrefs.fontSize = CGFloat(sender.doubleValue)
        findLabel(tag: 100)?.stringValue = "\(sender.integerValue) pt"
    }

    @objc private func fixedFontSizeChanged(_ sender: NSStepper) {
        YabomishPrefs.fixedFontSize = CGFloat(sender.doubleValue)
        findLabel(tag: 101)?.stringValue = "\(sender.integerValue) pt"
    }

    @objc private func toastSizeChanged(_ sender: NSStepper) {
        YabomishPrefs.toastFontSize = CGFloat(sender.doubleValue)
        findLabel(tag: 102)?.stringValue = "\(sender.integerValue) pt"
    }

    @objc private func autoCommitChanged(_ sender: NSButton) {
        YabomishPrefs.autoCommit = sender.state == .on
    }

    // MARK: - Layout helpers

    private func row(_ title: String, _ control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        return row
    }

    private func hStack(_ views: NSView...) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal; s.spacing = 4
        return s
    }

    private func findLabel(tag: Int) -> NSTextField? {
        contentView?.findView(tag: tag)
    }
}

private extension NSView {
    func findView<T: NSView>(tag: Int) -> T? {
        if self.tag == tag, let v = self as? T { return v }
        for sub in subviews {
            if let found: T = sub.findView(tag: tag) { return found }
        }
        return nil
    }
}
