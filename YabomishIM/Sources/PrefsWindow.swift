import Cocoa

final class PrefsWindow: NSPanel {
    static let shared = PrefsWindow()
    private var domainCollectionController: DomainCollectionController?

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 780),
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

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: bg.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let flipView = NSView()
        flipView.translatesAutoresizingMaskIntoConstraints = false
        flipView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: flipView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: flipView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: flipView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: flipView.bottomAnchor),
        ])
        scrollView.documentView = flipView
        NSLayoutConstraint.activate([
            flipView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        // ━━━ 字表（最重要，放最上面）━━━
        let cinInstalled = FileManager.default.fileExists(atPath: AppConstants.cinPath)
            || FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/YabomishIM/liu.cin")
            || FileManager.default.fileExists(atPath: AppConstants.sharedDir + "/liu.bin")

        if !cinInstalled {
            let guide = NSTextField(wrappingLabelWithString: "⚠️ 尚未匯入字表。請點擊下方「匯入字表」按鈕，選擇你的 .cin 檔案（例如 liu.cin）。匯入後即可開始使用。")
            guide.textColor = .systemOrange
            guide.font = .systemFont(ofSize: 13)
            stack.addArrangedSubview(guide)
        }

        stack.addArrangedSubview(sectionHeader("字表"))

        let importBtn = NSButton(title: cinInstalled ? "重新匯入字表⋯" : "匯入字表⋯", target: self, action: #selector(importCINClicked))
        importBtn.setAccessibilityLabel("匯入字表")
        importBtn.setAccessibilityHelp("選擇 .cin 檔案匯入主字表")
        let editExtrasBtn = NSButton(title: "編輯擴充表⋯", target: self, action: #selector(openExtrasFolder))
        editExtrasBtn.setAccessibilityLabel("編輯擴充表")
        editExtrasBtn.setAccessibilityHelp("打開擴充表資料夾")
        stack.addArrangedSubview(row("主字表", hStack(importBtn, editExtrasBtn)))

        if cinInstalled {
            let statusLabel = NSTextField(labelWithString: "✓ 字表已安裝")
            statusLabel.textColor = .systemGreen
            statusLabel.font = .systemFont(ofSize: 12)
            stack.addArrangedSubview(statusLabel)
        }

        let syncLabel = NSTextField(labelWithString: YabomishPrefs.syncFolder ?? "未設定")
        syncLabel.tag = 103
        syncLabel.lineBreakMode = .byTruncatingMiddle
        syncLabel.maximumNumberOfLines = 1
        syncLabel.preferredMaxLayoutWidth = 160
        let chooseBtn = NSButton(title: "選擇⋯", target: self, action: #selector(chooseSyncFolder))
        chooseBtn.setAccessibilityLabel("選擇同步資料夾")
        let clearBtn = NSButton(title: "清除", target: self, action: #selector(clearSyncFolder))
        clearBtn.setAccessibilityLabel("清除同步資料夾")
        stack.addArrangedSubview(row("同步資料夾", hStack(syncLabel, chooseBtn, clearBtn)))

        // ━━━ 選字窗 ━━━
        stack.addArrangedSubview(sectionHeader("選字窗"))

        let modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        modePopup.addItems(withTitles: ["游標跟隨", "固定位置"])
        modePopup.selectItem(at: YabomishPrefs.panelPosition == "fixed" ? 1 : 0)
        modePopup.target = self; modePopup.action = #selector(modeChanged(_:))
        modePopup.setAccessibilityLabel("選字窗模式")
        stack.addArrangedSubview(row("模式", modePopup))

        let alignPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        alignPopup.addItems(withTitles: ["靠左", "置中", "靠右"])
        let alignIdx = ["left": 0, "center": 1, "right": 2][YabomishPrefs.fixedAlignment] ?? 1
        alignPopup.selectItem(at: alignIdx)
        alignPopup.target = self; alignPopup.action = #selector(alignChanged(_:))
        alignPopup.setAccessibilityLabel("固定模式對齊方式")
        stack.addArrangedSubview(row("對齊（固定模式）", alignPopup))

        let alphaSlider = NSSlider(value: Double(YabomishPrefs.fixedAlpha), minValue: 0.3, maxValue: 1.0, target: self, action: #selector(alphaChanged(_:)))
        alphaSlider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        alphaSlider.setAccessibilityLabel("選字窗透明度")
        alphaSlider.toolTip = "30% ~ 100%"
        stack.addArrangedSubview(row("透明度", alphaSlider))

        let fontStepper = NSStepper(frame: .zero)
        fontStepper.minValue = 12; fontStepper.maxValue = 48; fontStepper.increment = 1
        fontStepper.integerValue = Int(YabomishPrefs.fontSize)
        fontStepper.target = self; fontStepper.action = #selector(fontSizeChanged(_:))
        fontStepper.setAccessibilityLabel("游標模式字體大小")
        fontStepper.toolTip = "12pt ~ 48pt"
        let fontLabel = NSTextField(labelWithString: "\(Int(YabomishPrefs.fontSize)) pt")
        fontLabel.tag = 100
        stack.addArrangedSubview(row("游標模式字體", hStack(fontLabel, fontStepper)))

        let fixedFontStepper = NSStepper(frame: .zero)
        fixedFontStepper.minValue = 12; fixedFontStepper.maxValue = 48; fixedFontStepper.increment = 1
        fixedFontStepper.integerValue = Int(YabomishPrefs.fixedFontSize)
        fixedFontStepper.target = self; fixedFontStepper.action = #selector(fixedFontSizeChanged(_:))
        fixedFontStepper.setAccessibilityLabel("固定模式字體大小")
        fixedFontStepper.toolTip = "12pt ~ 48pt"
        let fixedFontLabel = NSTextField(labelWithString: "\(Int(YabomishPrefs.fixedFontSize)) pt")
        fixedFontLabel.tag = 101
        stack.addArrangedSubview(row("固定模式字體", hStack(fixedFontLabel, fixedFontStepper)))

        // ━━━ 輸入 ━━━
        stack.addArrangedSubview(sectionHeader("輸入"))

        let autoBtn = NSButton(checkboxWithTitle: "滿碼自動送字", target: self, action: #selector(autoCommitChanged(_:)))
        autoBtn.state = YabomishPrefs.autoCommit ? .on : .off
        autoBtn.setAccessibilityHelp("輸入滿碼時自動送出候選字")
        stack.addArrangedSubview(autoBtn)

        let hintBtn = NSButton(checkboxWithTitle: "拆碼提示（送字後顯示嘸蝦米碼）", target: self, action: #selector(codeHintChanged(_:)))
        hintBtn.state = YabomishPrefs.showCodeHint ? .on : .off
        hintBtn.setAccessibilityHelp("送字後顯示該字的嘸蝦米拆碼")
        stack.addArrangedSubview(hintBtn)

        let zyBtn = NSButton(checkboxWithTitle: "注音反查（'; 切換）", target: self, action: #selector(zhuyinLookupChanged(_:)))
        zyBtn.state = YabomishPrefs.zhuyinReverseLookup ? .on : .off
        zyBtn.setAccessibilityHelp("按 '; 切換注音反查模式")
        stack.addArrangedSubview(zyBtn)

        // ━━━ 聯想 ━━━
        stack.addArrangedSubview(sectionHeader("聯想"))

        let strategyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        strategyPopup.addItems(withTitles: ["一般優先（詞→詞庫→字）", "專業優先（詞庫→詞→字）", "字級優先（字→詞→詞庫）"])
        let stratIdx = ["general": 0, "domain": 1, "char": 2][YabomishPrefs.suggestStrategy] ?? 0
        strategyPopup.selectItem(at: stratIdx)
        strategyPopup.target = self; strategyPopup.action = #selector(strategyChanged(_:))
        strategyPopup.toolTip = "決定詞級語料和詞庫的顯示順序"
        stack.addArrangedSubview(row("策略", strategyPopup))

        let corpusPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        corpusPopup.addItems(withTitles: ["萌典詞組", "維基斷詞", "台灣新聞斷詞"])
        let corpusIdx = ["moedict": 0, "wiki": 1, "news": 2][YabomishPrefs.wordCorpus] ?? 1
        corpusPopup.selectItem(at: corpusIdx)
        corpusPopup.target = self; corpusPopup.action = #selector(corpusChanged(_:))
        corpusPopup.toolTip = "選擇詞級聯想的語料來源"
        stack.addArrangedSubview(row("詞級語料", corpusPopup))

        let charSuggestBtn = NSButton(checkboxWithTitle: "字級聯想（bigram、trigram）", target: self, action: #selector(charSuggestChanged(_:)))
        charSuggestBtn.state = YabomishPrefs.charSuggest ? .on : .off
        charSuggestBtn.setAccessibilityHelp("使用 bigram/trigram 聯想下一字")
        stack.addArrangedSubview(charSuggestBtn)

        // ━━━ 外觀 ━━━
        stack.addArrangedSubview(sectionHeader("外觀"))

        let toastStepper = NSStepper(frame: .zero)
        toastStepper.minValue = 20; toastStepper.maxValue = 72; toastStepper.increment = 4
        toastStepper.integerValue = Int(YabomishPrefs.toastFontSize)
        toastStepper.target = self; toastStepper.action = #selector(toastSizeChanged(_:))
        toastStepper.setAccessibilityLabel("模式提示字體大小")
        toastStepper.toolTip = "20pt ~ 72pt"
        let toastLabel = NSTextField(labelWithString: "\(Int(YabomishPrefs.toastFontSize)) pt")
        toastLabel.tag = 102
        stack.addArrangedSubview(row("模式提示大小", hStack(toastLabel, toastStepper)))

        let activateBtn = NSButton(checkboxWithTitle: "切入時顯示模式提示", target: self, action: #selector(activateToastChanged(_:)))
        activateBtn.state = YabomishPrefs.showActivateToast ? .on : .off
        activateBtn.setAccessibilityHelp("切換到此輸入法時顯示模式提示")
        stack.addArrangedSubview(activateBtn)

        let iconPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        iconPopup.addItems(withTitles: ["← 向左", "→ 向右"])
        iconPopup.selectItem(at: YabomishPrefs.iconDirection == "right" ? 1 : 0)
        iconPopup.target = self; iconPopup.action = #selector(iconDirectionChanged(_:))
        iconPopup.setAccessibilityLabel("蝦頭方向")
        stack.addArrangedSubview(row("蝦頭方向", iconPopup))

        let labelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        labelPopup.addItems(withTitles: ["Yabo", "Yabomish"])
        labelPopup.selectItem(at: YabomishPrefs.menuBarLabel == "yabo" ? 0 : 1)
        labelPopup.target = self; labelPopup.action = #selector(menuBarLabelChanged(_:))
        labelPopup.setAccessibilityLabel("狀態列顯示")
        stack.addArrangedSubview(row("狀態列顯示", labelPopup))

        // ━━━ 詞庫（拖拉排序卡片）━━━
        let domainHint = NSTextField(labelWithString: "拖拉卡片調整順序，越靠左越優先。勾選啟用。")
        domainHint.font = .systemFont(ofSize: 11)
        domainHint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(domainHint)

        let domainCtrl = DomainCollectionController()
        stack.addArrangedSubview(domainCtrl.view)

        let applyBtn = NSButton(title: "套用", target: nil, action: nil)
        applyBtn.bezelStyle = .rounded
        applyBtn.target = self
        applyBtn.action = #selector(domainCardApply)
        stack.addArrangedSubview(hStack(applyBtn))
        self.domainCollectionController = domainCtrl

        // ━━━ 除錯 ━━━
        stack.addArrangedSubview(sectionHeader("除錯"))

        let debugBtn = NSButton(checkboxWithTitle: "Debug 模式（記錄操作日誌）", target: self, action: #selector(debugChanged(_:)))
        debugBtn.state = YabomishPrefs.debugMode ? .on : .off
        debugBtn.setAccessibilityHelp("開啟後會記錄操作日誌到 debug.log")
        stack.addArrangedSubview(debugBtn)

        let openLogBtn = NSButton(title: "打開 debug.log⋯", target: self, action: #selector(openDebugLog))
        openLogBtn.setAccessibilityLabel("打開除錯日誌")
        stack.addArrangedSubview(openLogBtn)

        // ━━━ Tab key navigation ━━━
        self.initialFirstResponder = importBtn
        importBtn.nextKeyView = editExtrasBtn
        editExtrasBtn.nextKeyView = chooseBtn
        chooseBtn.nextKeyView = clearBtn
        clearBtn.nextKeyView = modePopup
        modePopup.nextKeyView = alignPopup
        alignPopup.nextKeyView = alphaSlider
        alphaSlider.nextKeyView = fontStepper
        fontStepper.nextKeyView = fixedFontStepper
        fixedFontStepper.nextKeyView = autoBtn
        autoBtn.nextKeyView = hintBtn
        hintBtn.nextKeyView = zyBtn
        zyBtn.nextKeyView = strategyPopup
        strategyPopup.nextKeyView = corpusPopup
        corpusPopup.nextKeyView = charSuggestBtn
        charSuggestBtn.nextKeyView = toastStepper
        toastStepper.nextKeyView = activateBtn
        activateBtn.nextKeyView = iconPopup
        iconPopup.nextKeyView = debugBtn
        debugBtn.nextKeyView = openLogBtn
        openLogBtn.nextKeyView = importBtn
    }

    override var canBecomeKey: Bool { true }

    func showWindow() {
        NSApp.setActivationPolicy(.accessory)
        center()
        level = .floating
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        // IMKit 背景 App 有時第一次 activate 會被系統吃掉，延遲再試一次
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            self.makeKeyAndOrderFront(nil)
        }
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

    @objc private func strategyChanged(_ sender: NSPopUpButton) {
        let strategies = ["general", "domain", "char"]
        YabomishPrefs.suggestStrategy = strategies[sender.indexOfSelectedItem]
    }

    @objc private func corpusChanged(_ sender: NSPopUpButton) {
        let corpora = ["moedict", "wiki", "news"]
        YabomishPrefs.wordCorpus = corpora[sender.indexOfSelectedItem]
    }

    @objc private func charSuggestChanged(_ sender: NSButton) {
        YabomishPrefs.charSuggest = sender.state == .on
    }

    @objc private func domainCardApply() {
        domainCollectionController?.applyChanges()
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
        let label = sender.indexOfSelectedItem == 0 ? "yabo" : "yabomish"
        YabomishPrefs.menuBarLabel = label
        // Update Info.plist CFBundleName + CFBundleDisplayName
        guard let plistPath = Bundle.main.bundlePath.appending("/Contents/Info.plist") as String?,
              let dict = NSMutableDictionary(contentsOfFile: plistPath) else { return }
        let displayName = label == "yabo" ? "Yabo" : "Yabomish"
        dict["CFBundleName"] = displayName
        dict["CFBundleDisplayName"] = displayName
        dict.write(toFile: plistPath, atomically: true)
        showReinstallAlert()
    }

    @objc private func importCINClicked() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, .text, .data]
        panel.message = "選擇字表（.cin）或擴充表（.txt）"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        let cinFiles = panel.urls.filter { $0.pathExtension.lowercased() == "cin" }
        let txtFiles = panel.urls.filter { $0.pathExtension.lowercased() == "txt" }

        // .cin → 匯入主表
        if let cin = cinFiles.first {
            YabomishInputController.importCIN(from: cin, attachedTo: self)
        }

        // .txt → 複製到 tables/
        if !txtFiles.isEmpty {
            let dir = NSHomeDirectory() + "/Library/YabomishIM/tables"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            var imported: [String] = []
            for url in txtFiles {
                let dst = dir + "/" + url.lastPathComponent
                try? FileManager.default.removeItem(atPath: dst)
                try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: dst))
                imported.append(url.lastPathComponent)
            }
            YabomishInputController.reloadTable()
            let a = NSAlert()
            a.messageText = "已匯入 \(imported.count) 個擴充表"
            a.informativeText = imported.joined(separator: "\n") + "\n\n字表已自動重載。"
            a.runModal()
        }
    }

    @objc private func openExtrasFolder() {
        let dir = NSHomeDirectory() + "/Library/YabomishIM/tables"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
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

    private func sectionHeader(_ title: String) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 4
        container.alignment = .leading

        let sep = NSBox()
        sep.boxType = .separator
        container.addArrangedSubview(sep)

        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        container.addArrangedSubview(label)

        return container
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
