import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ClipboardProcessor {

    /// Read plain text from clipboard (strips all formatting)
    static func plainText() -> String? {
        #if os(macOS)
        NSPasteboard.general.string(forType: .string)
        #else
        UIPasteboard.general.string
        #endif
    }

    /// Read HTML from clipboard and convert to Markdown
    static func htmlToMarkdown() -> String? {
        #if os(macOS)
        guard let htmlData = NSPasteboard.general.data(forType: .html)
                          ?? NSPasteboard.general.string(forType: .html)?.data(using: .utf8)
        else { return plainText() }
        return _htmlDataToMarkdown(htmlData) ?? plainText()
        #else
        return plainText()
        #endif
    }

    /// Simplified → Traditional Chinese
    static func toTraditional(_ text: String) -> String {
        text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
    }

    /// Traditional → Simplified Chinese
    static func toSimplified(_ text: String) -> String {
        text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
    }

    // MARK: - HTML → Markdown via XMLDocument

    #if os(macOS)
    private static func _htmlDataToMarkdown(_ data: Data) -> String? {
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        // Wrap fragment in full HTML doc with charset for proper parsing
        let full: String
        if html.lowercased().contains("<html") {
            full = html
        } else {
            full = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>\(html)</body></html>"
        }
        // Must use xmlString: (not data:) to preserve CJK characters
        guard let doc = try? XMLDocument(xmlString: full, options: [.documentTidyHTML]) else {
            return nil
        }
        guard let body = _findBody(doc.rootElement()) ?? doc.rootElement() else {
            return nil
        }
        var ctx = MDContext()
        _walk(body, ctx: &ctx)
        var result = ctx.output
        // collapse 3+ newlines
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n",
                                             options: .regularExpression)
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct MDContext {
        var output = ""
        var listDepth = 0
        var orderedIndex: [Int] = []  // stack of counters for nested <ol>
        var inPre = false
    }

    private static func _findBody(_ el: XMLElement?) -> XMLElement? {
        guard let el = el else { return nil }
        if el.localName?.lowercased() == "body" { return el }
        for child in el.children ?? [] {
            if let found = _findBody(child as? XMLElement) { return found }
        }
        return nil
    }

    private static func _walk(_ node: XMLNode, ctx: inout MDContext) {
        if node.kind == .text {
            let text = node.stringValue ?? ""
            if ctx.inPre {
                ctx.output += text
            } else {
                // collapse whitespace in normal flow
                let collapsed = text.replacingOccurrences(of: "\\s+", with: " ",
                                                          options: .regularExpression)
                ctx.output += collapsed
            }
            return
        }

        guard let el = node as? XMLElement else {
            for child in node.children ?? [] { _walk(child, ctx: &ctx) }
            return
        }

        let tag = el.localName?.lowercased() ?? ""

        switch tag {
        // Headings
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(tag.last!))!
            _ensureNewline(&ctx)
            ctx.output += String(repeating: "#", count: level) + " "
            _walkChildren(el, ctx: &ctx)
            ctx.output += "\n\n"

        // Paragraphs
        case "p":
            _ensureNewline(&ctx)
            _walkChildren(el, ctx: &ctx)
            ctx.output += "\n\n"

        // Line break
        case "br":
            ctx.output += "\n"

        // Bold
        case "b", "strong":
            ctx.output += "**"
            _walkChildren(el, ctx: &ctx)
            ctx.output += "**"

        // Italic
        case "i", "em":
            ctx.output += "*"
            _walkChildren(el, ctx: &ctx)
            ctx.output += "*"

        // Strikethrough
        case "s", "del", "strike":
            ctx.output += "~~"
            _walkChildren(el, ctx: &ctx)
            ctx.output += "~~"

        // Code (inline)
        case "code":
            if !ctx.inPre {
                ctx.output += "`"
                _walkChildren(el, ctx: &ctx)
                ctx.output += "`"
            } else {
                _walkChildren(el, ctx: &ctx)
            }

        // Pre (code block)
        case "pre":
            _ensureNewline(&ctx)
            ctx.output += "```\n"
            ctx.inPre = true
            _walkChildren(el, ctx: &ctx)
            ctx.inPre = false
            if !ctx.output.hasSuffix("\n") { ctx.output += "\n" }
            ctx.output += "```\n\n"

        // Links
        case "a":
            let href = el.attribute(forName: "href")?.stringValue ?? ""
            ctx.output += "["
            _walkChildren(el, ctx: &ctx)
            ctx.output += "](\(href))"

        // Images
        case "img":
            let src = el.attribute(forName: "src")?.stringValue ?? ""
            let alt = el.attribute(forName: "alt")?.stringValue ?? ""
            ctx.output += "![\(alt)](\(src))"

        // Unordered list
        case "ul":
            _ensureNewline(&ctx)
            ctx.listDepth += 1
            _walkChildren(el, ctx: &ctx)
            ctx.listDepth -= 1
            if ctx.listDepth == 0 { ctx.output += "\n" }

        // Ordered list
        case "ol":
            _ensureNewline(&ctx)
            ctx.listDepth += 1
            ctx.orderedIndex.append(0)
            _walkChildren(el, ctx: &ctx)
            ctx.orderedIndex.removeLast()
            ctx.listDepth -= 1
            if ctx.listDepth == 0 { ctx.output += "\n" }

        // List item
        case "li":
            let indent = String(repeating: "  ", count: max(0, ctx.listDepth - 1))
            let bullet: String
            if !ctx.orderedIndex.isEmpty {
                ctx.orderedIndex[ctx.orderedIndex.count - 1] += 1
                bullet = "\(ctx.orderedIndex.last!). "
            } else {
                bullet = "- "
            }
            ctx.output += indent + bullet
            _walkChildren(el, ctx: &ctx)
            if !ctx.output.hasSuffix("\n") { ctx.output += "\n" }

        // Table
        case "table":
            _ensureNewline(&ctx)
            _walkTable(el, ctx: &ctx)

        // Blockquote
        case "blockquote":
            _ensureNewline(&ctx)
            var inner = MDContext()
            inner.listDepth = ctx.listDepth
            _walkChildren(el, ctx: &inner)
            let lines = inner.output.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")
            for line in lines { ctx.output += "> \(line)\n" }
            ctx.output += "\n"

        // Horizontal rule
        case "hr":
            _ensureNewline(&ctx)
            ctx.output += "---\n\n"

        // Skip
        case "head", "style", "script", "meta", "link":
            break

        // Div, span, etc — just recurse
        default:
            _walkChildren(el, ctx: &ctx)
        }
    }

    private static func _walkChildren(_ el: XMLElement, ctx: inout MDContext) {
        for child in el.children ?? [] { _walk(child, ctx: &ctx) }
    }

    private static func _ensureNewline(_ ctx: inout MDContext) {
        if !ctx.output.isEmpty && !ctx.output.hasSuffix("\n") {
            ctx.output += "\n"
        }
    }

    // MARK: - Table → Markdown

    private static func _walkTable(_ table: XMLElement, ctx: inout MDContext) {
        var rows: [[String]] = []
        var hasHeader = false

        for node in table.children ?? [] {
            guard let section = node as? XMLElement else { continue }
            let sectionTag = section.localName?.lowercased() ?? ""
            if sectionTag == "thead" { hasHeader = true }
            let rowEls = (sectionTag == "tr") ? [section] : _findElements(section, tag: "tr")
            for tr in rowEls {
                var cells: [String] = []
                for cell in tr.children ?? [] {
                    guard let cellEl = cell as? XMLElement else { continue }
                    let t = cellEl.localName?.lowercased() ?? ""
                    if t == "td" || t == "th" {
                        if t == "th" { hasHeader = true }
                        var cellCtx = MDContext()
                        _walkChildren(cellEl, ctx: &cellCtx)
                        cells.append(cellCtx.output.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
                if !cells.isEmpty { rows.append(cells) }
            }
        }

        guard !rows.isEmpty else { return }
        let cols = rows.map(\.count).max() ?? 0
        // Pad rows
        let padded = rows.map { $0 + Array(repeating: "", count: max(0, cols - $0.count)) }

        // Header row
        let header = padded[0]
        ctx.output += "| " + header.joined(separator: " | ") + " |\n"
        ctx.output += "| " + header.map { _ in "---" }.joined(separator: " | ") + " |\n"

        // Body rows
        let start = hasHeader ? 1 : 0
        for i in start..<padded.count {
            ctx.output += "| " + padded[i].joined(separator: " | ") + " |\n"
        }
        ctx.output += "\n"
    }

    private static func _findElements(_ el: XMLElement, tag: String) -> [XMLElement] {
        var result: [XMLElement] = []
        for child in el.children ?? [] {
            guard let childEl = child as? XMLElement else { continue }
            if childEl.localName?.lowercased() == tag { result.append(childEl) }
            else { result += _findElements(childEl, tag: tag) }
        }
        return result
    }
    #endif
}
