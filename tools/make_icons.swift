// 產生 menubar/輸入法圖示 template TIFF（16+32px，LZW）
// 用法：swift tools/make_icons.swift   → 寫入 YabomishIM/Resources/
// 規格：黑底圓角方塊＋白字鏤空（Apple 官方輸入法徽章）；TISIconIsTemplate=true
//       只讀 alpha，深淺色選單列自動適配。fn/Globe 輸入源切換器讀同一組圖。
import AppKit
import Foundation

let res = "YabomishIM/Resources"

func badge(_ text: String, font: NSFont, size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)  // points == pixels → 72dpi
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let r = CGFloat(size) * 0.28
    NSColor.black.setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: r, yRadius: r).fill()
    let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
    let ts = str.size()
    str.draw(at: NSPoint(x: (CGFloat(size) - ts.width) / 2,
                         y: (CGFloat(size) - ts.height) / 2 - CGFloat(size) * 0.015))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writeTIFF(_ lo: NSBitmapImageRep, _ hi: NSBitmapImageRep, to out: String) {
    let dir = NSTemporaryDirectory() + UUID().uuidString
    try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let f1 = dir + "/1x.png", f2 = dir + "/2x.png"
    try! lo.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: f1))
    try! hi.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: f2))
    for args in [["-cathidpicheck", f1, f2, "-out", out],
                 ["-lzw", out, "-out", out + ".lzw"]] {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
        p.arguments = args
        try! p.run(); p.waitUntilExit()
    }
    try? FileManager.default.removeItem(atPath: out)
    try! FileManager.default.moveItem(atPath: out + ".lzw", toPath: out)
    try? FileManager.default.removeItem(atPath: dir)
    print("wrote \(out)")
}

func pingfang(_ size: CGFloat) -> NSFont {
    NSFont(name: "PingFangTC-Semibold", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
}

// zh：蝦（PingFang TC 中黑）
writeTIFF(badge("蝦", font: pingfang(11), size: 16),
          badge("蝦", font: pingfang(22), size: 32), to: "\(res)/icon.tiff")
// en mode：A
writeTIFF(badge("A", font: .systemFont(ofSize: 11, weight: .bold), size: 16),
          badge("A", font: .systemFont(ofSize: 22, weight: .bold), size: 32), to: "\(res)/icon_en.tiff")
// dev 變體：β
writeTIFF(badge("β", font: .systemFont(ofSize: 13, weight: .bold), size: 16),
          badge("β", font: .systemFont(ofSize: 26, weight: .bold), size: 32), to: "\(res)/icon_dev.tiff")
