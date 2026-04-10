import Cocoa

// MARK: - DomainOrderManager

final class DomainOrderManager {
    static let shared = DomainOrderManager()
    private let defaults = UserDefaults.standard
    private let orderKey = "domainOrder"

    func orderedKeys(for group: [(key: String, file: String, label: String)]) -> [String] {
        let saved = defaults.stringArray(forKey: orderKey) ?? []
        let groupKeys = group.map { $0.key }
        var ordered = saved.filter { groupKeys.contains($0) }
        for k in groupKeys where !ordered.contains(k) { ordered.append(k) }
        return ordered
    }

    func allOrderedKeys() -> [String] {
        let saved = defaults.stringArray(forKey: orderKey) ?? []
        let allKeys = WikiCorpus.domainKeys.map { $0.key }
        var ordered = saved.filter { allKeys.contains($0) }
        for k in allKeys where !ordered.contains(k) { ordered.append(k) }
        return ordered
    }

    func saveOrder(_ keys: [String]) { defaults.set(keys, forKey: orderKey) }
    func isEnabled(_ key: String) -> Bool { YabomishPrefs.domainEnabled(key) }
    func setEnabled(_ key: String, _ val: Bool) { YabomishPrefs.setDomainEnabled(key, val) }
}

// MARK: - DomainCard (single draggable card view)

private final class DomainCard: NSView {
    let key: String
    private let cardBox = NSBox()
    private let checkbox = NSButton()
    private let nameLabel = NSTextField()
    private let colorBar = NSView()
    private let barColor: NSColor
    var onToggle: ((String, Bool) -> Void)?

    init(key: String, label: String, color: NSColor, enabled: Bool) {
        self.key = key
        self.barColor = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        cardBox.boxType = .custom; cardBox.cornerRadius = 8
        cardBox.borderWidth = 1; cardBox.borderColor = .separatorColor
        cardBox.contentViewMargins = .zero
        cardBox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardBox)

        colorBar.wantsLayer = true
        colorBar.translatesAutoresizingMaskIntoConstraints = false
        cardBox.addSubview(colorBar)

        checkbox.setButtonType(.switch); checkbox.title = ""
        checkbox.state = enabled ? .on : .off
        checkbox.target = self; checkbox.action = #selector(toggled)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.setAccessibilityLabel(label)
        cardBox.addSubview(checkbox)

        nameLabel.stringValue = label
        nameLabel.isEditable = false; nameLabel.isBordered = false; nameLabel.drawsBackground = false
        nameLabel.font = .systemFont(ofSize: 12); nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        cardBox.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            cardBox.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardBox.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardBox.topAnchor.constraint(equalTo: topAnchor),
            cardBox.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 140),
            heightAnchor.constraint(equalToConstant: 40),
            colorBar.leadingAnchor.constraint(equalTo: cardBox.leadingAnchor),
            colorBar.topAnchor.constraint(equalTo: cardBox.topAnchor, constant: 1),
            colorBar.bottomAnchor.constraint(equalTo: cardBox.bottomAnchor, constant: -1),
            colorBar.widthAnchor.constraint(equalToConstant: 4),
            checkbox.leadingAnchor.constraint(equalTo: colorBar.trailingAnchor, constant: 6),
            checkbox.centerYAnchor.constraint(equalTo: cardBox.centerYAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: cardBox.trailingAnchor, constant: -6),
            nameLabel.centerYAnchor.constraint(equalTo: cardBox.centerYAnchor),
        ])
        updateVisual(enabled)
        registerForDraggedTypes([.string])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        colorBar.layer?.backgroundColor = barColor.cgColor
    }

    private func updateVisual(_ on: Bool) {
        cardBox.fillColor = on ? .controlBackgroundColor : .windowBackgroundColor
        cardBox.alphaValue = on ? 1.0 : 0.5
    }

    @objc private func toggled() {
        let on = checkbox.state == .on
        DomainOrderManager.shared.setEnabled(key, on)
        updateVisual(on)
        onToggle?(key, on)
    }

    // Drag source
    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        // If click is on checkbox area, let it handle
        if checkbox.frame.contains(loc) { super.mouseDown(with: event); return }
        // Start drag
        let item = NSDraggingItem(pasteboardWriter: NSString(string: key))
        item.setDraggingFrame(bounds, contents: snapshot())
        beginDraggingSession(with: [item], event: event, source: self)
    }

    private func snapshot() -> NSImage {
        let img = NSImage(size: bounds.size)
        img.lockFocus()
        cardBox.alphaValue = 0.7
        displayIgnoringOpacity(bounds, in: NSGraphicsContext.current!)
        cardBox.alphaValue = checkbox.state == .on ? 1.0 : 0.5
        img.unlockFocus()
        return img
    }
}

extension DomainCard: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
}

// MARK: - DomainCardRow (a row of cards that supports drag reorder)

final class DomainCardRow: NSView {
    private var cards: [DomainCard] = []
    private let stackView = NSStackView()
    private let sectionColor: NSColor
    private var orderedKeys: [String]
    private let groupKeys: [(key: String, file: String, label: String)]

    init(title: String, group: [(key: String, file: String, label: String)], color: NSColor) {
        self.groupKeys = group
        self.sectionColor = color
        self.orderedKeys = DomainOrderManager.shared.orderedKeys(for: group)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: title)
        header.font = .boldSystemFont(ofSize: 13)
        header.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .horizontal
        stackView.spacing = 8
        stackView.alignment = .centerY
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSStackView(views: [header, stackView])
        wrapper.orientation = .vertical
        wrapper.alignment = .leading
        wrapper.spacing = 6
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        addSubview(wrapper)
        NSLayoutConstraint.activate([
            wrapper.leadingAnchor.constraint(equalTo: leadingAnchor),
            wrapper.trailingAnchor.constraint(equalTo: trailingAnchor),
            wrapper.topAnchor.constraint(equalTo: topAnchor),
            wrapper.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        rebuildCards()
        registerForDraggedTypes([.string])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func rebuildCards() {
        cards.forEach { $0.removeFromSuperview() }
        cards.removeAll()
        let labelMap = Dictionary(uniqueKeysWithValues: groupKeys.map { ($0.key, $0.label) })
        for key in orderedKeys {
            let card = DomainCard(key: key, label: labelMap[key] ?? key,
                                  color: sectionColor,
                                  enabled: DomainOrderManager.shared.isEnabled(key))
            cards.append(card)
            stackView.addArrangedSubview(card)
        }
    }

    // Drop target
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let key = sender.draggingPasteboard.string(forType: .string),
              orderedKeys.contains(key) else { return [] }
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let key = sender.draggingPasteboard.string(forType: .string),
              orderedKeys.contains(key) else { return [] }
        return .move
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let draggedKey = sender.draggingPasteboard.string(forType: .string),
              let srcIdx = orderedKeys.firstIndex(of: draggedKey) else { return false }

        let loc = convert(sender.draggingLocation, from: nil)
        // Find insertion index based on x position
        var dstIdx = cards.count
        for (i, card) in cards.enumerated() {
            let mid = card.frame.midX
            if loc.x < mid { dstIdx = i; break }
        }
        if dstIdx == srcIdx || dstIdx == srcIdx + 1 { return false }

        orderedKeys.remove(at: srcIdx)
        let insertAt = dstIdx > srcIdx ? dstIdx - 1 : dstIdx
        orderedKeys.insert(draggedKey, at: insertAt)

        // Persist
        let groupKeySet = Set(groupKeys.map { $0.key })
        let allOrdered = DomainOrderManager.shared.allOrderedKeys()
        var newOrder: [String] = []
        var groupInserted = false
        for k in allOrdered {
            if groupKeySet.contains(k) {
                if !groupInserted { newOrder.append(contentsOf: orderedKeys); groupInserted = true }
            } else {
                newOrder.append(k)
            }
        }
        if !groupInserted { newOrder.append(contentsOf: orderedKeys) }
        DomainOrderManager.shared.saveOrder(newOrder)

        // Animate
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            rebuildCards()
        }
        return true
    }
}
