import AppKit

/// 個性化文字樣式共用解析：候選窗與模式提示 HUD 由同一組
/// toastFontStyle / toastTextColor / toastStroke / toastStrokeColor 偏好驅動。
enum TextStyle {
    /// 字體：system / rounded（Yuanti TC→SF Rounded）/ serif（明體 Songti TC）/
    /// heiti（黑體 PingFang TC→Heiti TC）/ kaiti（楷體 Kaiti TC→STKaiti）
    static func font(style: String, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        switch style {
        case "rounded":
            // .rounded 設計只換拉丁為 SF Rounded，中文仍落回 PingFang——
            // Yuanti TC 才是真 CJK 圓體；缺字體時才退 .rounded
            if let f = namedFont("Yuanti TC", size: size, weight: weight) { return f }
            if let desc = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.rounded),
               let f = NSFont(descriptor: desc, size: size) { return f }
        case "serif", "heiti", "kaiti":
            let names: [String]
            switch style {
            case "serif": names = ["Songti TC"]
            case "heiti": names = ["PingFang TC", "Heiti TC"]
            default:      names = ["Kaiti TC", "STKaiti"]
            }
            for n in names {
                if let f = namedFont(n, size: size, weight: weight) { return f }
            }
        default:
            break
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// 具名字體＋可選粗體：NSFont(name:) 只回常規體，weight 靠 symbolicTraits 補
    private static func namedFont(_ name: String, size: CGFloat, weight: NSFont.Weight) -> NSFont? {
        guard let base = NSFont(name: name, size: size) else { return nil }
        guard weight.rawValue >= NSFont.Weight.semibold.rawValue,
              let bold = NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(.bold),
                                size: size) else { return base }
        return bold
    }

    /// 描邊粗細 px → NSStrokeWidthAttributeName（字號百分比，負值＝填色＋外框並存）
    static func strokePercent(px: Double, fontSize: CGFloat) -> Double {
        -(px / Double(fontSize) * 100)
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
