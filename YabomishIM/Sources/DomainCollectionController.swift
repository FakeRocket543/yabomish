import Cocoa

/// Manages the drag-reorder card UI for domain/corpus settings.
final class DomainCollectionController {
    private let container = NSStackView()
    private let generalRow: DomainCardRow
    private let proRow: DomainCardRow

    var view: NSView { container }

    init() {
        generalRow = DomainCardRow(title: "詞庫", group: WikiCorpus.generalDomainKeys, color: .systemBlue)
        proRow = DomainCardRow(title: "專業詞典", group: WikiCorpus.proDomainKeys, color: .systemOrange)

        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 16
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addArrangedSubview(generalRow)
        container.addArrangedSubview(proRow)
    }

    func applyChanges() {
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
