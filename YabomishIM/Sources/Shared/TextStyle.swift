import AppKit

/// 個性化文字樣式共用解析：候選窗與模式提示 HUD 由同一組
/// toastFontStyle / toastTextColor / toastStroke / toastStrokeColor 偏好驅動。
enum TextStyle {
    /// 字體：system / rounded（SF Rounded）/ serif（明體 Songti TC）/ heiti（黑體 PingFang TC→Heiti TC→系統體）
    static func font(style: String, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        switch style {
        case "rounded":
            if let desc = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.rounded),
               let f = NSFont(descriptor: desc, size: size) { return f }
        case "serif":
            if let f = NSFont(name: "Songti TC", size: size) { return f }
        case "heiti":
            if let f = NSFont(name: "PingFang TC", size: size) { return f }
            if let f = NSFont(name: "Heiti TC", size: size) { return f }
        default:
            break
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// "#RRGGBB" → NSColor（解析失敗回 fallback）
    static func color(_ hex: String, fallback: NSColor) -> NSColor {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return fallback }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
