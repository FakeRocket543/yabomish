import Cocoa

/// Manages the drag-reorder NSCollectionView for domain/corpus cards.
/// Three sections: 詞庫 / 流行語 / 專業詞典
final class DomainCollectionController: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {

    private let collectionView: NSCollectionView
    private let scrollView: NSScrollView
    private let dragType = NSPasteboard.PasteboardType("com.yabomish.domain-card")

    // Section definitions: (title, color, keys)
    private struct Section {
        let title: String
        let color: NSColor
        var keys: [String]  // ordered domain keys
    }
    private var sections: [Section] = []

    /// The assembled scroll view to embed in PrefsWindow.
    var view: NSView { scrollView }

    override init() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 130, height: 44)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.headerReferenceSize = NSSize(width: 0, height: 28)
        layout.sectionInset = NSEdgeInsets(top: 4, left: 4, bottom: 12, right: 4)

        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]

        scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        super.init()

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(DomainCardItem.self, forItemWithIdentifier: DomainCardItem.identifier)
        collectionView.register(DomainSectionHeader.self,
                                forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                                withIdentifier: DomainSectionHeader.identifier)
        collectionView.registerForDraggedTypes([dragType])
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)

        loadSections()
    }

    private func loadSections() {
        let mgr = DomainOrderManager.shared
        let genKeys = mgr.orderedKeys(for: WikiCorpus.generalDomainKeys)
        let proKeys = mgr.orderedKeys(for: WikiCorpus.proDomainKeys)
        sections = [
            Section(title: "詞庫", color: .systemBlue, keys: genKeys),
            Section(title: "專業詞典", color: .systemOrange, keys: proKeys),
        ]
        collectionView.reloadData()
    }

    private func domainInfo(_ key: String) -> (key: String, file: String, label: String)? {
        WikiCorpus.domainKeys.first { $0.key == key }
    }

    // MARK: - DataSource

    func numberOfSections(in collectionView: NSCollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].keys.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: DomainCardItem.identifier, for: indexPath) as! DomainCardItem
        let key = sections[indexPath.section].keys[indexPath.item]
        let info = domainInfo(key)
        let color = sections[indexPath.section].color
        item.configure(key: key, labelText: info?.label ?? key, color: color,
                       enabled: DomainOrderManager.shared.isEnabled(key))
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSView {
        let header = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: DomainSectionHeader.identifier, for: indexPath) as! DomainSectionHeader
        header.titleLabel.stringValue = sections[indexPath.section].title
        return header
    }

    // MARK: - Drag & Drop

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool { true }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString("\(indexPath.section):\(indexPath.item)", forType: dragType)
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        // Only allow reorder within same section
        guard let data = draggingInfo.draggingPasteboard.string(forType: dragType),
              let srcSection = Int(data.split(separator: ":").first ?? "") else { return [] }
        if srcSection != proposedDropIndexPath.pointee.section { return [] }
        proposedDropOperation.pointee = .before
        return .move
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        guard let data = draggingInfo.draggingPasteboard.string(forType: dragType),
              let parts = Optional(data.split(separator: ":")),
              parts.count == 2,
              let srcSection = Int(parts[0]),
              let srcItem = Int(parts[1]),
              srcSection == indexPath.section else { return false }

        var keys = sections[srcSection].keys
        let moving = keys.remove(at: srcItem)
        let dst = srcItem < indexPath.item ? indexPath.item - 1 : indexPath.item
        keys.insert(moving, at: dst)
        sections[srcSection].keys = keys

        collectionView.animator().moveItem(at: IndexPath(item: srcItem, section: srcSection),
                                           to: IndexPath(item: dst, section: srcSection))
        persistOrder()
        return true
    }

    private func persistOrder() {
        let allKeys = sections.flatMap { $0.keys }
        DomainOrderManager.shared.saveOrder(allKeys)
    }

    // MARK: - Layout

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> NSSize {
        NSSize(width: collectionView.bounds.width, height: 28)
    }

    // MARK: - Apply

    func applyChanges() {
        persistOrder()
        DispatchQueue.global(qos: .userInitiated).async {
            WikiCorpus.shared.reloadDomains()
            DispatchQueue.main.async {
                let a = NSAlert()
                a.messageText = "詞庫已更新"
                a.informativeText = "已載入 \(WikiCorpus.shared.domainBinCount) 個詞庫。\n拖拉順序 = 優先順序（越靠左越優先）"
                a.runModal()
            }
        }
    }
}
