import Cocoa

/// Custom candidate panel replacing buggy IMKCandidates.
/// Supports two modes:
///   - "cursor": vertical list near cursor (original)
///   - "fixed": horizontal bar above Dock, semi-transparent, draggable, right-click menu
final class CandidatePanel: NSPanel {
    static let shared = CandidatePanel()

    // MARK: - Shared state

    private var candidates: [String] = []
    private var selKeys: [Character] = []
    private var highlightIndex = 0
    private let pageSize = 9

    // MARK: - Cursor-mode views

    private let stackView = NSStackView()
    private var labels: [NSTextField] = []
    private var pageIndicator: NSTextField!

    private var stackConstraints: [NSLayoutConstraint] = []

    // MARK: - Fixed-mode views

    private let fixedLabel = NSTextField(labelWithString: "")
    private var dragOffset: NSPoint = .zero
    private var composingText = ""
    var targetScreen: NSScreen?
    var modeTag: String = ""  // 當前模式標籤（非 "繁中" 時顯示）

    private var isFixed: Bool { YabomishPrefs.panelPosition == "fixed" }
    private var effectiveScreen: NSScreen { targetScreen ?? NSScreen.main ?? NSScreen.screens[0] }

    // MARK: - Init

    private init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        self.level = .popUpMenu
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let contentVisual = NSVisualEffectView()
        contentVisual.material = .popover
        contentVisual.state = .active
        contentVisual.wantsLayer = true
        contentVisual.layer?.cornerRadius = 6
        self.contentView = contentVisual

        // --- Cursor-mode setup (original) ---
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 1
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        contentVisual.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackConstraints = [
            stackView.topAnchor.constraint(equalTo: contentVisual.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentVisual.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentVisual.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentVisual.bottomAnchor),
        ]
        NSLayoutConstraint.activate(stackConstraints)

        for _ in 0..<pageSize {
            let label = NSTextField(labelWithString: "")
            label.font = NSFont.monospacedSystemFont(ofSize: YabomishPrefs.fontSize, weight: .regular)
            label.isBordered = false
            label.isEditable = false
            label.wantsLayer = true
            label.layer?.cornerRadius = 3
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            stackView.addArrangedSubview(label)
            labels.append(label)
        }

        pageIndicator = NSTextField(labelWithString: "")
        pageIndicator.font = NSFont.systemFont(ofSize: 11)
        pageIndicator.isBordered = false
        pageIndicator.isEditable = false
        pageIndicator.isHidden = true
        stackView.addArrangedSubview(pageIndicator)

        // --- Fixed-mode setup ---
        fixedLabel.font = .systemFont(ofSize: YabomishPrefs.fixedFontSize)
        fixedLabel.textColor = .labelColor
        fixedLabel.alignment = .center
        fixedLabel.isBordered = false
        fixedLabel.isEditable = false
        fixedLabel.translatesAutoresizingMaskIntoConstraints = false
        fixedLabel.isHidden = true
        contentVisual.addSubview(fixedLabel)
        NSLayoutConstraint.activate([
            fixedLabel.leadingAnchor.constraint(equalTo: contentVisual.leadingAnchor, constant: 12),
            fixedLabel.trailingAnchor.constraint(equalTo: contentVisual.trailingAnchor, constant: -12),
            fixedLabel.centerYAnchor.constraint(equalTo: contentVisual.centerYAnchor),
        ])

        // Hover cursor for fixed mode
        let tracking = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        contentVisual.addTrackingArea(tracking)

        // Screen change observer
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    @objc private func screenParametersChanged() {
        if isFixed && isVisible { repositionFixed() }
    }

    // MARK: - Public API

    /// When true, cursor mode falls back to fixed-mode display (incompatible apps)
    var fallbackFixed = false

    func show(candidates: [String], selKeys: [Character], at origin: NSPoint, composing: String = "") {
        guard !candidates.isEmpty else { hide(); return }
        self.candidates = candidates
        self.selKeys = selKeys
        self.highlightIndex = 0
        self.composingText = composing

        if isFixed || fallbackFixed {
            showFixed()
        } else {
            showCursor(at: origin)
        }
    }

    func hide() {
        if (isFixed || fallbackFixed) && isVisible {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                animator().alphaValue = 0
            }, completionHandler: {
                self.orderOut(nil)
            })
        } else {
            orderOut(nil)
        }
        candidates = []
        composingText = ""
    }

    func selectByKey(_ c: Character) -> String? {
        guard let idx = selKeys.firstIndex(of: c) else { return nil }
        let i = selKeys.distance(from: selKeys.startIndex, to: idx)
        let actual = pageStart + i
        guard actual < candidates.count else { return nil }
        return candidates[actual]
    }

    func pageDown() {
        let newStart = pageStart + pageSize
        if newStart < candidates.count {
            highlightIndex = newStart
            rebuildCurrentMode()
        }
    }

    func pageUp() {
        highlightIndex = max(0, pageStart - pageSize)
        rebuildCurrentMode()
    }

    func moveUp() {
        if highlightIndex > 0 { highlightIndex -= 1; rebuildCurrentMode() }
    }

    func moveDown() {
        if highlightIndex < candidates.count - 1 { highlightIndex += 1; rebuildCurrentMode() }
    }

    /// Navigate prev/next — caller uses this for arrow keys matching layout direction
    func movePrev() { moveUp() }
    func moveNext() { moveDown() }

    var isFixedMode: Bool { isFixed || fallbackFixed }

    func selectedCandidate() -> String? {
        guard highlightIndex < candidates.count else { return nil }
        return candidates[highlightIndex]
    }

    var isVisible_: Bool { isVisible }

    private var pageStart: Int { (highlightIndex / pageSize) * pageSize }

    private func keyLabel(_ c: Character) -> String {
        let fullWidthDigits: [Character] = ["０","１","２","３","４","５","６","７","８","９"]
        if let d = c.wholeNumberValue, d < 10 { return String(fullWidthDigits[d]) }
        return String(c)
    }

    private func rebuildCurrentMode() {
        if isFixed || fallbackFixed { rebuildFixedLabel() } else { rebuildLabels() }
    }

    // MARK: - Cursor mode (original vertical layout)

    private func showCursor(at origin: NSPoint) {
        switchToCursorLayout()
        rebuildLabels()
        positionWindow(at: origin)
        orderFront(nil)
    }

    private func switchToCursorLayout() {
        stackView.isHidden = false
        fixedLabel.isHidden = true
        NSLayoutConstraint.activate(stackConstraints)
        alphaValue = 1.0
        (contentView as? NSVisualEffectView)?.material = .popover
        (contentView as? NSVisualEffectView)?.layer?.cornerRadius = 6
    }

    private func rebuildLabels() {
        let fontSize = YabomishPrefs.fontSize
        let start = pageStart
        let end = min(start + pageSize, candidates.count)

        for i in 0..<pageSize {
            let label = labels[i]
            label.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            if start + i < end {
                let candIdx = start + i
                let keyChar = i < selKeys.count ? keyLabel(selKeys[i]) : " "
                label.stringValue = "\(keyChar)\(candidates[candIdx])"
                label.isHidden = false
                if candIdx == highlightIndex {
                    label.drawsBackground = true
                    label.backgroundColor = NSColor.selectedContentBackgroundColor
                    label.textColor = .selectedMenuItemTextColor
                } else {
                    label.drawsBackground = false
                    label.backgroundColor = .clear
                    label.textColor = .labelColor
                }
            } else {
                label.isHidden = true
            }
        }

        let totalPages = (candidates.count + pageSize - 1) / pageSize
        if totalPages > 1 {
            let currentPage = pageStart / pageSize + 1
            pageIndicator.stringValue = "  \(currentPage)/\(totalPages)"
            pageIndicator.textColor = .secondaryLabelColor
            pageIndicator.isHidden = false
        } else {
            pageIndicator.isHidden = true
        }

        layoutIfNeeded()
        let size = stackView.fittingSize
        let maxW: CGFloat = 360
        setContentSize(NSSize(width: min(max(size.width + 12, 80), maxW), height: size.height))
    }

    private func positionWindow(at origin: NSPoint) {
        let screen = effectiveScreen
        var pt = origin
        pt.y -= (self.frame.height + 4)
        if pt.y < screen.visibleFrame.minY { pt.y = origin.y + 20 }
        if pt.x + frame.width > screen.visibleFrame.maxX {
            pt.x = screen.visibleFrame.maxX - frame.width
        }
        setFrameOrigin(pt)
    }

    // MARK: - Fixed mode (horizontal bar above Dock)

    private func showFixed() {
        let wasVisible = isVisible
        switchToFixedLayout()
        rebuildFixedLabel()
        repositionFixed()
        if !wasVisible {
            alphaValue = 0
            orderFront(nil)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                self.animator().alphaValue = YabomishPrefs.fixedAlpha
            })
        } else {
            orderFront(nil)
        }
    }

    private func switchToFixedLayout() {
        NSLayoutConstraint.deactivate(stackConstraints)
        stackView.isHidden = true
        fixedLabel.isHidden = false
        (contentView as? NSVisualEffectView)?.material = .hudWindow
        (contentView as? NSVisualEffectView)?.layer?.cornerRadius = 8
    }

    private func rebuildFixedLabel() {
        let start = pageStart
        let end = min(start + pageSize, candidates.count)
        let sep = "  "
        let font = NSFont.systemFont(ofSize: YabomishPrefs.fixedFontSize)
        fixedLabel.font = font
        let normalAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let highlightAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.selectedMenuItemTextColor,
            .backgroundColor: NSColor.selectedContentBackgroundColor,
        ]

        let result = NSMutableAttributedString()

        if !composingText.isEmpty {
            result.append(NSAttributedString(string: "[\(composingText)]" + sep, attributes: normalAttrs))
        }

        for i in start..<end {
            if i > start { result.append(NSAttributedString(string: sep, attributes: normalAttrs)) }
            let keyIdx = i - start
            let keyChar = keyIdx < selKeys.count ? keyLabel(selKeys[keyIdx]) : " "
            let text = "\(keyChar)\(candidates[i])"
            let attrs = (i == highlightIndex) ? highlightAttrs : normalAttrs
            result.append(NSAttributedString(string: text, attributes: attrs))
        }

        let totalPages = (candidates.count + pageSize - 1) / pageSize
        if totalPages > 1 {
            let currentPage = pageStart / pageSize + 1
            result.append(NSAttributedString(string: sep + "◀ \(currentPage)/\(totalPages) ▶", attributes: normalAttrs))
        }

        if !modeTag.isEmpty && modeTag != "繁中" {
            let tagFont = NSFont.systemFont(ofSize: YabomishPrefs.fixedFontSize * 0.65)
            let tagAttrs: [NSAttributedString.Key: Any] = [
                .font: tagFont, .foregroundColor: NSColor.secondaryLabelColor
            ]
            result.append(NSAttributedString(string: sep + "[\(modeTag)]", attributes: tagAttrs))
        }

        fixedLabel.attributedStringValue = result

        let size = fixedLabel.intrinsicContentSize
        let h = size.height + 8
        let screen = effectiveScreen
        let maxW = screen.frame.width * 0.85
        setContentSize(NSSize(width: min(size.width + 24, maxW), height: h))
    }

    private func repositionFixed() {
        let screen = effectiveScreen
        let dockH = dockBottomHeight(screen: screen)
        let y = screen.frame.minY + dockH + YabomishPrefs.fixedYOffset

        let x: CGFloat
        switch YabomishPrefs.fixedAlignment {
        case "left":   x = screen.frame.minX + 16
        case "right":  x = screen.frame.maxX - frame.width - 16
        default:       x = screen.frame.midX - frame.width / 2
        }
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func dockBottomHeight(screen: NSScreen) -> CGFloat {
        let diff = screen.visibleFrame.minY - screen.frame.minY
        return max(diff, 0)
    }

    // MARK: - Fixed mode: hover cursor

    override func mouseEntered(with event: NSEvent) {
        if isFixed { NSCursor.openHand.push() }
    }

    override func mouseExited(with event: NSEvent) {
        if isFixed { NSCursor.pop() }
    }

    // MARK: - Fixed mode: dragging (vertical only)

    override func mouseDown(with event: NSEvent) {
        if isFixed {
            dragOffset = event.locationInWindow
            NSCursor.closedHand.push()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isFixed else { super.mouseDragged(with: event); return }
        let screen = effectiveScreen
        let newY = frame.origin.y + (event.locationInWindow.y - dragOffset.y)
        let clampedY = max(screen.frame.minY, min(newY, screen.frame.maxY - frame.height))
        setFrameOrigin(NSPoint(x: frame.origin.x, y: clampedY))
    }

    override func mouseUp(with event: NSEvent) {
        guard isFixed else { super.mouseUp(with: event); return }
        let screen = effectiveScreen
        NSCursor.pop()
        let dockH = dockBottomHeight(screen: screen)
        YabomishPrefs.fixedYOffset = frame.origin.y - screen.frame.minY - dockH
    }

    // MARK: - Fixed mode: right-click context menu

    override func rightMouseDown(with event: NSEvent) {
        guard isFixed else { super.rightMouseDown(with: event); return }

        let menu = NSMenu()

        // Alignment
        for (title, key) in [("靠左", "left"), ("置中", "center"), ("靠右", "right")] {
            let item = NSMenuItem(title: title, action: #selector(menuSetAlignment(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            if YabomishPrefs.fixedAlignment == key { item.state = .on }
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // Transparency submenu
        let alphaMenu = NSMenu()
        for pct in stride(from: 100, through: 30, by: -10) {
            let item = NSMenuItem(title: "\(pct)%", action: #selector(menuSetAlpha(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = CGFloat(pct) / 100.0
            if abs(YabomishPrefs.fixedAlpha - CGFloat(pct) / 100.0) < 0.05 { item.state = .on }
            alphaMenu.addItem(item)
        }
        let alphaItem = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        alphaItem.submenu = alphaMenu
        menu.addItem(alphaItem)

        menu.addItem(.separator())

        // Font size submenu
        let fontMenu = NSMenu()
        for size in stride(from: 14, through: 48, by: 2) {
            let item = NSMenuItem(title: "\(size)pt", action: #selector(menuSetFontSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = CGFloat(size)
            if abs(YabomishPrefs.fixedFontSize - CGFloat(size)) < 1 { item.state = .on }
            fontMenu.addItem(item)
        }
        let fontItem = NSMenuItem(title: "字體大小", action: nil, keyEquivalent: "")
        fontItem.submenu = fontMenu
        menu.addItem(fontItem)

        menu.addItem(.separator())

        // Mode toggle
        let toggleTitle = isFixed ? "切換到游標跟隨" : "切換到固定位置"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(menuToggleMode), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        NSMenu.popUpContextMenu(menu, with: event, for: contentView!)
    }

    @objc private func menuSetAlignment(_ sender: NSMenuItem) {
        YabomishPrefs.fixedAlignment = sender.representedObject as! String
        repositionFixed()
    }

    @objc private func menuSetAlpha(_ sender: NSMenuItem) {
        let a = sender.representedObject as! CGFloat
        YabomishPrefs.fixedAlpha = a
        alphaValue = a
    }

    @objc private func menuSetFontSize(_ sender: NSMenuItem) {
        YabomishPrefs.fixedFontSize = sender.representedObject as! CGFloat
        rebuildFixedLabel()
        repositionFixed()
    }

    @objc private func menuToggleMode() {
        YabomishPrefs.panelPosition = isFixed ? "cursor" : "fixed"
        hide()
    }
}
