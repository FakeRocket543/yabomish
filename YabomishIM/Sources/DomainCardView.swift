import Cocoa

// MARK: - DomainOrderManager

/// Manages domain ordering and enabled state. Persists to UserDefaults.
/// Order is stored as an array of domain keys; position = priority.
final class DomainOrderManager {
    static let shared = DomainOrderManager()
    private let defaults = UserDefaults.standard
    private let orderKey = "domainOrder"

    /// Returns ordered domain keys for a group. Position = priority (index 0 = highest).
    func orderedKeys(for group: [(key: String, file: String, label: String)]) -> [String] {
        let saved = defaults.stringArray(forKey: orderKey) ?? []
        let groupKeys = group.map { $0.key }
        // Preserve saved order for keys in this group, append any new keys at end
        var ordered = saved.filter { groupKeys.contains($0) }
        for k in groupKeys where !ordered.contains(k) { ordered.append(k) }
        return ordered
    }

    /// Returns all domain keys in saved order (across all groups).
    func allOrderedKeys() -> [String] {
        let saved = defaults.stringArray(forKey: orderKey) ?? []
        let allKeys = WikiCorpus.domainKeys.map { $0.key }
        var ordered = saved.filter { allKeys.contains($0) }
        for k in allKeys where !ordered.contains(k) { ordered.append(k) }
        return ordered
    }

    /// Save the full ordered key list.
    func saveOrder(_ keys: [String]) {
        defaults.set(keys, forKey: orderKey)
    }

    func isEnabled(_ key: String) -> Bool { YabomishPrefs.domainEnabled(key) }
    func setEnabled(_ key: String, _ val: Bool) { YabomishPrefs.setDomainEnabled(key, val) }
}

// MARK: - DomainCardItem (NSCollectionViewItem)

final class DomainCardItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("DomainCardItem")
    private let cardBox = NSBox()
    private let colorBar = NSView()
    private let checkbox = NSButton()
    private let label = NSTextField()
    private var domainKey = ""

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 130, height: 44))

        cardBox.boxType = .custom
        cardBox.cornerRadius = 8
        cardBox.borderWidth = 1
        cardBox.borderColor = .separatorColor
        cardBox.fillColor = .controlBackgroundColor
        cardBox.contentViewMargins = .zero
        cardBox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardBox)

        colorBar.wantsLayer = true
        colorBar.translatesAutoresizingMaskIntoConstraints = false
        cardBox.addSubview(colorBar)

        checkbox.setButtonType(.switch)
        checkbox.title = ""
        checkbox.target = self
        checkbox.action = #selector(toggled)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        cardBox.addSubview(checkbox)

        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cardBox.addSubview(label)

        NSLayoutConstraint.activate([
            cardBox.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cardBox.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cardBox.topAnchor.constraint(equalTo: view.topAnchor),
            cardBox.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            colorBar.leadingAnchor.constraint(equalTo: cardBox.leadingAnchor),
            colorBar.topAnchor.constraint(equalTo: cardBox.topAnchor, constant: 1),
            colorBar.bottomAnchor.constraint(equalTo: cardBox.bottomAnchor, constant: -1),
            colorBar.widthAnchor.constraint(equalToConstant: 4),
            checkbox.leadingAnchor.constraint(equalTo: colorBar.trailingAnchor, constant: 6),
            checkbox.centerYAnchor.constraint(equalTo: cardBox.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cardBox.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cardBox.centerYAnchor),
        ])
    }

    func configure(key: String, labelText: String, color: NSColor, enabled: Bool) {
        domainKey = key
        label.stringValue = labelText
        checkbox.state = enabled ? .on : .off
        colorBar.layer?.backgroundColor = color.cgColor
        updateVisual(enabled)
    }

    private func updateVisual(_ enabled: Bool) {
        cardBox.fillColor = enabled ? .controlBackgroundColor : .windowBackgroundColor
        cardBox.alphaValue = enabled ? 1.0 : 0.5
    }

    @objc private func toggled() {
        let on = checkbox.state == .on
        DomainOrderManager.shared.setEnabled(domainKey, on)
        updateVisual(on)
    }
}

// MARK: - DomainCardSection

/// A section view (header) for NSCollectionView.
final class DomainSectionHeader: NSView, NSCollectionViewSectionHeaderView {
    static let identifier = NSUserInterfaceItemIdentifier("DomainSectionHeader")
    let titleLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}
