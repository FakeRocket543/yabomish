import Cocoa

/// Custom candidate panel replacing buggy IMKCandidates.
/// Uses NSPanel for proper window level control and key handling.
final class CandidatePanel: NSPanel {
    static let shared = CandidatePanel()

    private let stackView = NSStackView()
    private let scrollView = NSScrollView()
    private var labels: [NSTextField] = []
    private var candidates: [String] = []
    private var selKeys: [Character] = []
    private var highlightIndex = 0
    private let pageSize = 9

    private init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        self.level = .popUpMenu
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let visual = NSVisualEffectView()
        visual.material = .popover
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 6
        self.contentView = visual

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 1
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)

        visual.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: visual.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: visual.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: visual.bottomAnchor),
        ])
    }

    func show(candidates: [String], selKeys: [Character], at origin: NSPoint) {
        guard !candidates.isEmpty else { hide(); return }
        self.candidates = candidates
        self.selKeys = selKeys
        self.highlightIndex = 0
        rebuildLabels()
        positionWindow(at: origin)
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
        candidates = []
    }

    /// Returns selected candidate string, or nil if index invalid
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
            rebuildLabels()
        }
    }

    func pageUp() {
        let newStart = pageStart - pageSize
        highlightIndex = max(0, newStart)
        rebuildLabels()
    }

    var isVisible_: Bool { isVisible }

    private var pageStart: Int {
        (highlightIndex / pageSize) * pageSize
    }

    private func rebuildLabels() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        labels.removeAll()

        let start = pageStart
        let end = min(start + pageSize, candidates.count)

        for i in start..<end {
            let keyIdx = i - start
            let keyLabel = keyIdx < selKeys.count ? "\(selKeys[keyIdx]). " : "  "
            let text = "\(keyLabel)\(candidates[i])"

            let label = NSTextField(labelWithString: text)
            label.font = NSFont.systemFont(ofSize: 16)
            label.textColor = .labelColor
            label.backgroundColor = .clear
            label.isBordered = false
            label.isEditable = false

            if i == highlightIndex {
                label.backgroundColor = NSColor.controlAccentColor
                label.textColor = .white
                label.wantsLayer = true
                label.layer?.cornerRadius = 3
            }

            stackView.addArrangedSubview(label)
            labels.append(label)
        }

        // Page indicator
        let totalPages = (candidates.count + pageSize - 1) / pageSize
        let currentPage = pageStart / pageSize + 1
        if totalPages > 1 {
            let indicator = NSTextField(labelWithString: "  \(currentPage)/\(totalPages)")
            indicator.font = NSFont.systemFont(ofSize: 11)
            indicator.textColor = .secondaryLabelColor
            stackView.addArrangedSubview(indicator)
        }

        layoutIfNeeded()
        let size = stackView.fittingSize
        setContentSize(NSSize(width: max(size.width + 12, 80), height: size.height))
    }

    private func positionWindow(at origin: NSPoint) {
        guard let screen = NSScreen.main else { return }
        var pt = origin
        pt.y -= (self.frame.height + 4) // below the cursor

        // Keep on screen
        if pt.y < screen.visibleFrame.minY {
            pt.y = origin.y + 20 // flip above
        }
        if pt.x + frame.width > screen.visibleFrame.maxX {
            pt.x = screen.visibleFrame.maxX - frame.width
        }
        setFrameOrigin(pt)
    }
}
