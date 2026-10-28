import SwiftUI

/// Color ↔ "#RRGGBB" hex 字串轉換（偏好以 hex 字串儲存，ColorPicker 需要 Color）。
extension Color {
    init(hex: String, fallback: Color = .white) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { self = fallback; return }
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension Binding where Value == String {
    /// 把 hex 字串 binding 包成 Color binding（ColorPicker 用）。
    func asColor() -> Binding<Color> {
        Binding<Color>(
            get: { Color(hex: wrappedValue) },
            set: { wrappedValue = $0.hexString }
        )
    }
}
