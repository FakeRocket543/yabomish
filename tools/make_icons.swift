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
    // lo(16px) 用 points==pixels（72dpi）；hi(32px) 由 writeTIFF 設 16pt → 144dpi @2x
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let r = CGFloat(size) * 0.28
    // 彩色模式（TISIconIsTemplate=false）：黑底圓角＋白色實心字，
    // RGB 直出（fn HUD 全彩、menubar 系統會去飽和但形狀清楚）
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
    // @2x 幀標 16pt/32px（144dpi）——Apple 官方 TIFF 即 72+144 配對；
    // 兩幀都 72dpi 時系統不當它是 Aqua 1x/2x 對，Retina menubar 解不出圖示
    hi.size = NSSize(width: CGFloat(hi.pixelsWide) / 2, height: CGFloat(hi.pixelsHigh) / 2)
    try! lo.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: f1))
    try! hi.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: f2))
    for args in [["-cathidpicheck", f1, f2, "-out", out],
                 ["-lzw", out, "-out", out + ".lzw"]] {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
        p.arguments = args
        try! p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            FileHandle.standardError.write("tiffutil \(args.first!) failed (exit \(p.terminationStatus))\n".data(using: .utf8)!)
            exit(1)  // 失敗時絕不能留下半成品/舊檔被 -lzw 重包裝
        }
    }
    try? FileManager.default.removeItem(atPath: out)
    try! FileManager.default.moveItem(atPath: out + ".lzw", toPath: out)
    patch2xDPI(out)
    try? FileManager.default.removeItem(atPath: dir)
    print("wrote \(out)")
}

/// tiffutil -cathidpicheck 一律把兩幀寫成 72dpi；Apple 官方 TIFF 的 @2x 幀是 144dpi。
/// Aqua 多重解析 TIFF 靠 72+144 配對標記 1x/2x——直接改寫第二個 IFD 的 XRes/YRes 分子。
func patch2xDPI(_ path: String) {
    var d = try! Data(contentsOf: URL(fileURLWithPath: path))
    let be = d[0] == 0x4D  // tiffutil 輸出 MM（big-endian）
    func u16(_ o: Int) -> Int { be ? Int(d[o])<<8 | Int(d[o+1]) : Int(d[o]) | Int(d[o+1])<<8 }
    func u32(_ o: Int) -> Int { u16(o)<<16 | u16(o+2) }
    func put32(_ o: Int, _ v: Int) {
        let b: [UInt8] = be ? [UInt8(v>>24&255), UInt8(v>>16&255), UInt8(v>>8&255), UInt8(v&255)]
                            : [UInt8(v&255), UInt8(v>>8&255), UInt8(v>>16&255), UInt8(v>>24&255)]
        for i in 0..<4 { d[o+i] = b[i] }
    }
    var ifd = u32(4), idx = 0
    while ifd != 0 {
        if idx == 1 {  // @2x 幀
            let n = u16(ifd)
            for i in 0..<n where u16(ifd+2+i*12) == 282 || u16(ifd+2+i*12) == 283 {
                let valOff = u32(ifd+2+i*12+8)  // RATIONAL (8B)：分子/分母
                put32(valOff, 144); put32(valOff+4, 1)
            }
        }
        let n = u16(ifd)
        ifd = u32(ifd+2+n*12); idx += 1
    }
    try! d.write(to: URL(fileURLWithPath: path))
}

func pingfang(_ size: CGFloat) -> NSFont {
    NSFont(name: "PingFangTC-Semibold", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
}

/// 炸蝦剪影 template mask：rsvg 直出像素 → 二值化（深色不透明、其餘全透明）。
/// SVG 內的白色切口線是「畫上去的白」而非 alpha 洞——template 只讀 alpha，
/// 直接用會變實心蝦；以亮度臨界把切口打成真透明。
func shrimpMask(svgPath: String, px: Int) -> NSBitmapImageRep {
    let png = "/tmp/shrimp_\(px).png"
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/rsvg-convert")
    p.arguments = ["-w", "\(px)", "-h", "\(px)", svgPath, "-o", png]
    try! p.run(); p.waitUntilExit()
    guard p.terminationStatus == 0,
          let src = (NSBitmapImageRep.imageReps(withContentsOfFile: png) as? [NSBitmapImageRep])?.first
    else { FileHandle.standardError.write("rsvg-convert failed for \(svgPath)\n".data(using: .utf8)!); exit(1) }
    // 彩色版：RGB 原樣直出（Twemoji 原色），alpha 保真
    return src
}

// zh：彩色炸蝦（Twemoji 原色；assets/menubar-friedshrimp-color.svg）
writeTIFF(shrimpMask(svgPath: "assets/menubar-friedshrimp-color.svg", px: 16),
          shrimpMask(svgPath: "assets/menubar-friedshrimp-color.svg", px: 32), to: "\(res)/icon.tiff")
// en mode：A
writeTIFF(badge("A", font: .systemFont(ofSize: 11, weight: .bold), size: 16),
          badge("A", font: .systemFont(ofSize: 22, weight: .bold), size: 32), to: "\(res)/icon_en.tiff")
// dev 變體：β
writeTIFF(badge("β", font: .systemFont(ofSize: 13, weight: .bold), size: 16),
          badge("β", font: .systemFont(ofSize: 26, weight: .bold), size: 32), to: "\(res)/icon_dev.tiff")
