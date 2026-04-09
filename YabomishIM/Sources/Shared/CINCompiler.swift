import Foundation

/// Compiles a .cin text file into CINM binary format for mmap loading.
/// Called from App side after user imports a .cin file.
///
/// ⚠️  IMPORTANT: .cin files are copyrighted by their respective authors (e.g. 嘸蝦米 by 行易).
///    This compiler runs ON-DEVICE at import time only.
///    NEVER pre-compile or bundle .bin files — they are derived from copyrighted material.
enum CINCompiler {

    /// Compile cin at `srcPath` → write bin to `dstPath`. Returns entry count or 0 on failure.
    @discardableResult
    static func compile(src srcPath: String, dst dstPath: String) -> Int {
        guard let data = FileManager.default.contents(atPath: srcPath),
              let content = String(data: data, encoding: .utf8) else { return 0 }

        var entries: [(code: String, chars: [String])] = []
        var codeMap: [String: Int] = [:]  // code → index in entries
        var selkeys = "0123456789"
        var cname = ""
        var inChardef = false

        content.enumerateLines { line, _ in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("%selkey ") {
                selkeys = String(t.dropFirst(8)).trimmingCharacters(in: .whitespaces); return
            }
            if t.hasPrefix("%cname ") {
                cname = String(t.dropFirst(7)).trimmingCharacters(in: .whitespaces); return
            }
            if t == "%chardef begin" { inChardef = true; return }
            if t == "%chardef end" { inChardef = false; return }
            guard inChardef else { return }
            let parts: [String]
            if t.contains("\t") { parts = t.split(separator: "\t", maxSplits: 1).map(String.init) }
            else { parts = t.split(separator: " ", maxSplits: 1).map(String.init) }
            guard parts.count == 2 else { return }
            let code = parts[0].lowercased()
            let char = parts[1].trimmingCharacters(in: .whitespaces)
            if let idx = codeMap[code] {
                entries[idx].chars.append(char)
            } else {
                codeMap[code] = entries.count
                entries.append((code, [char]))
            }
        }

        // Sort by code (ASCII order)
        entries.sort { $0.code < $1.code }
        guard !entries.isEmpty else { return 0 }

        // Build strings section
        var stringsBuf = Data()
        var codeEntries: [(off: Int, len: Int)] = []
        for e in entries {
            let b = e.code.data(using: .ascii) ?? Data()
            codeEntries.append((stringsBuf.count, b.count))
            stringsBuf.append(b)
        }

        // Build chars section
        var charsBuf = Data()
        var valEntries: [(off: Int, cnt: Int)] = []
        for e in entries {
            let off = charsBuf.count / 4
            var cnt = 0
            for ch in e.chars {
                for scalar in ch.unicodeScalars {
                    var cp = scalar.value.littleEndian
                    charsBuf.append(Data(bytes: &cp, count: 4))
                    cnt += 1
                }
            }
            valEntries.append((off, cnt))
        }

        // Header (128 bytes)
        let headerSize = 128
        var header = Data(count: headerSize)
        header[0] = 0x43; header[1] = 0x49; header[2] = 0x4E; header[3] = 0x4D // "CINM"
        header.writeU32(4, UInt32(entries.count))
        let skData = selkeys.data(using: .ascii) ?? Data()
        header[8] = UInt8(min(skData.count, 10))
        header.replaceSubrange(9..<(9 + min(skData.count, 10)), with: skData.prefix(10))
        let cnData = (cname.data(using: .utf8) ?? Data()).prefix(64)
        header.writeU16(20, UInt16(cnData.count))
        header.replaceSubrange(22..<(22 + cnData.count), with: cnData)

        // Code index
        var codeIdx = Data()
        for e in codeEntries {
            codeIdx.appendU32(UInt32(e.off))
            codeIdx.appendU16(UInt16(e.len))
        }

        // Val index
        var valIdx = Data()
        for e in valEntries {
            guard e.off <= Int(UInt16.max) else {
                NSLog("CINCompiler: val offset %d exceeds UInt16 range, clamping", e.off)
                valIdx.appendU16(UInt16.max)
                valIdx.append(UInt8(min(e.cnt, 255)))
                valIdx.append(0)
                continue
            }
            valIdx.appendU16(UInt16(e.off))
            valIdx.append(UInt8(min(e.cnt, 255)))
            valIdx.append(0) // reserved
        }

        // Section offsets
        let codesOff = headerSize
        let valsOff = codesOff + codeIdx.count
        let stringsOff = valsOff + valIdx.count
        let charsOff = stringsOff + stringsBuf.count
        header.writeU32(96, UInt32(codesOff))
        header.writeU32(100, UInt32(valsOff))
        header.writeU32(104, UInt32(stringsOff))
        header.writeU32(108, UInt32(charsOff))

        // Assemble + write
        var buf = header
        buf.append(codeIdx)
        buf.append(valIdx)
        buf.append(stringsBuf)
        buf.append(charsBuf)

        do {
            try buf.write(to: URL(fileURLWithPath: dstPath))
            return entries.count
        } catch {
            return 0
        }
    }
}

// MARK: - Data write helpers
private extension Data {
    mutating func writeU32(_ off: Int, _ v: UInt32) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { replaceSubrange(off..<(off+4), with: $0) }
    }
    mutating func writeU16(_ off: Int, _ v: UInt16) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { replaceSubrange(off..<(off+2), with: $0) }
    }
    mutating func appendU32(_ v: UInt32) {
        var le = v.littleEndian
        append(Data(bytes: &le, count: 4))
    }
    mutating func appendU16(_ v: UInt16) {
        var le = v.littleEndian
        append(Data(bytes: &le, count: 2))
    }
}
