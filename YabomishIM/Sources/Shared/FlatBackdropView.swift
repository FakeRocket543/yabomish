import AppKit

/// 「無視覺效果」用的純色不透明圓角背景。
/// 顏色隨所在 window 的 appearance 解析深淺色；
/// 供 HUD（YabomishInputController）與候選窗（CandidatePanel）共用。
final class FlatBackdropView: NSView {
    var radius: CGFloat = 0
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
}
