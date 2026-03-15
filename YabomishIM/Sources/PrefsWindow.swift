import Cocoa

final class PrefsWindow: NSPanel {
    static let shared = PrefsWindow()

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 560),
                   styleMask: [.titled, .closable],
                   backing: .buffered, defer: true)
        self.title = "Yabomish 偏好設定"
        self.level = .floating
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

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
        fontStepper.minValue = 12; fontStepper.maxValue = 48; fontStepper.increment = 1
        fontStepper.integerValue = Int(YabomishPrefs.fontSize)
        fontStepper.target = self; fontStepper.action = #selector(fontSizeChanged(_:))
        let fontLabel = NSTextField(labelWithString: "\(Int(YabomishPrefs.fontSize)) pt")
        fontLabel.tag = 100
        let fontRow = row("游標模式字體", hStack(fontLabel, fontStepper))
        stack.addArrangedSubview(fontRow)

        // — 固定模式字體大小 —
        let fixedFontStepper = NSStepper(frame: .zero)
        fixedFontStepper.minValue = 12; fixedFontStepper.maxValue = 48; fixedFontStepper.increment = 1
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

        // — 拆碼提示 —
        let hintBtn = NSButton(checkboxWithTitle: "拆碼提示（送字後顯示嘸蝦米碼）", target: self, action: #selector(codeHintChanged(_:)))
        hintBtn.state = YabomishPrefs.showCodeHint ? .on : .off
        stack.addArrangedSubview(hintBtn)

        // — 注音反查 —
        let zyBtn = NSButton(checkboxWithTitle: "注音反查（'; 切換）", target: self, action: #selector(zhuyinLookupChanged(_:)))
        zyBtn.state = YabomishPrefs.zhuyinReverseLookup ? .on : .off
        stack.addArrangedSubview(zyBtn)

        // — 切入時顯示模式 —
        let activateBtn = NSButton(checkboxWithTitle: "切入時顯示模式提示", target: self, action: #selector(activateToastChanged(_:)))
        activateBtn.state = YabomishPrefs.showActivateToast ? .on : .off
        stack.addArrangedSubview(activateBtn)

        // — 蝦頭方向 —
        let iconPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        iconPopup.addItems(withTitles: ["← 向左", "→ 向右"])
        iconPopup.selectItem(at: YabomishPrefs.iconDirection == "right" ? 1 : 0)
        iconPopup.target = self; iconPopup.action = #selector(iconDirectionChanged(_:))
        stack.addArrangedSubview(row("蝦頭方向", iconPopup))

        // — 狀態列名稱 —
        let labelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        labelPopup.addItems(withTitles: ["Yabo", "Yabomish"])
        let labelIdx = ["yabo": 0, "yabomish": 1][YabomishPrefs.menuBarLabel] ?? 1
        labelPopup.selectItem(at: labelIdx)
        labelPopup.target = self; labelPopup.action = #selector(menuBarLabelChanged(_:))
        stack.addArrangedSubview(row("狀態列名稱", labelPopup))

        // — 匯入字表 —
        let importBtn = NSButton(title: "匯入字表⋯", target: self, action: #selector(importCINClicked))
        stack.addArrangedSubview(importBtn)

        // — 字頻同步資料夾 —
        let syncLabel = NSTextField(labelWithString: YabomishPrefs.syncFolder ?? "未設定")
        syncLabel.tag = 103
        syncLabel.lineBreakMode = .byTruncatingMiddle
        syncLabel.maximumNumberOfLines = 1
        syncLabel.preferredMaxLayoutWidth = 160
        let chooseBtn = NSButton(title: "選擇⋯", target: self, action: #selector(chooseSyncFolder))
        let clearBtn = NSButton(title: "清除", target: self, action: #selector(clearSyncFolder))
        stack.addArrangedSubview(row("字頻同步資料夾", hStack(syncLabel, chooseBtn, clearBtn)))

        // — Debug —
        let debugBtn = NSButton(checkboxWithTitle: "Debug 模式（記錄操作日誌）", target: self, action: #selector(debugChanged(_:)))
        debugBtn.state = YabomishPrefs.debugMode ? .on : .off
        stack.addArrangedSubview(debugBtn)

        let openLogBtn = NSButton(title: "打開 debug.log⋯", target: self, action: #selector(openDebugLog))
        stack.addArrangedSubview(openLogBtn)
    }

    override var canBecomeKey: Bool { true }

    func showWindow() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        level = .floating
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

    @objc private func codeHintChanged(_ sender: NSButton) {
        YabomishPrefs.showCodeHint = sender.state == .on
    }

    @objc private func zhuyinLookupChanged(_ sender: NSButton) {
        YabomishPrefs.zhuyinReverseLookup = sender.state == .on
    }

    @objc private func activateToastChanged(_ sender: NSButton) {
        YabomishPrefs.showActivateToast = sender.state == .on
    }

    @objc private func iconDirectionChanged(_ sender: NSPopUpButton) {
        let dir = sender.indexOfSelectedItem == 1 ? "right" : "left"
        YabomishPrefs.iconDirection = dir
        guard let resPath = Bundle.main.resourcePath else { return }
        let src = "\(resPath)/icon_\(dir).tiff"
        let dst = "\(resPath)/icon.tiff"
        guard FileManager.default.fileExists(atPath: src) else { return }
        try? FileManager.default.removeItem(atPath: dst)
        try? FileManager.default.copyItem(atPath: src, toPath: dst)
        showReinstallAlert()
    }

    @objc private func menuBarLabelChanged(_ sender: NSPopUpButton) {
        let keys = ["yabo", "yabomish"]
        YabomishPrefs.menuBarLabel = keys[sender.indexOfSelectedItem]
        showReinstallAlert()
    }

    @objc private func importCINClicked() {
        YabomishInputController.importCIN(attachedTo: self)
    }

    @objc private func chooseSyncFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "選擇"
        panel.message = "選擇字頻同步資料夾（建議 iCloud Drive 內的資料夾）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        YabomishPrefs.syncFolder = url.path
        findLabel(tag: 103)?.stringValue = url.path
        let a = NSAlert()
        a.messageText = "需要重新啟動輸入法"
        a.informativeText = "字頻同步路徑已設定為：\n\(url.path)\n\n請登出再登入以套用。"
        a.runModal()
    }

    @objc private func clearSyncFolder() {
        YabomishPrefs.syncFolder = nil
        findLabel(tag: 103)?.stringValue = "未設定"
    }

    @objc private func debugChanged(_ sender: NSButton) {
        YabomishPrefs.debugMode = sender.state == .on
        if sender.state == .on {
            DebugLog.log("Debug mode enabled")
        }
    }

    @objc private func openDebugLog() {
        let path = NSHomeDirectory() + "/Library/YabomishIM/debug.log"
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            let a = NSAlert()
            a.messageText = "尚無日誌"
            a.informativeText = "請先開啟 Debug 模式並操作一段時間。"
            a.runModal()
        }
    }

    private func showReinstallAlert() {
        let alert = NSAlert()
        alert.messageText = "需要重新安裝"
        alert.informativeText = "請執行 install.sh 並重新登入後生效。"
        alert.alertStyle = .informational
        alert.runModal()
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
