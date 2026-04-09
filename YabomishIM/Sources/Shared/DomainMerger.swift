import Foundation

/// Merges selected domain term bins into a single WBMM binary at App Support.
enum DomainMerger {
    static func merge() {
        var merged: [String: [String]] = [:]

        for (key, file, _) in WikiCorpus.domainKeys {
            guard YabomishPrefs.domainEnabled(key),
                  let p = Bundle.main.path(forResource: file, ofType: "bin"),
                  let d = try? Data(contentsOf: URL(fileURLWithPath: p), options: .mappedIfSafe),
                  d.count >= 16, d[0] == 0x57, d[1] == 0x42, d[2] == 0x4D, d[3] == 0x4D else { continue }

            let kc = Int(d.u32(4)), ki = Int(d.u32(8)), vi = Int(d.u32(12))
            guard ki <= d.count, vi <= d.count else { continue }
            for i in 0..<kc {
                let eo = ki + i * 12
                guard eo + 12 <= d.count else { break }
                let so = Int(d.u32(eo)), sl = Int(d.u16(eo + 4))
                let vs = Int(d.u32(eo + 6)), vc = Int(d.u16(eo + 10))
                guard so >= 0, so + sl <= d.count else { continue }
                guard let k = String(data: d[so..<(so + sl)], encoding: .utf8) else { continue }
                var vals = merged[k] ?? []
                let seen = Set(vals)
                for j in 0..<vc {
                    let vo = vi + (vs + j) * 6
                    guard vo + 6 <= d.count else { break }
                    let vso = Int(d.u32(vo)), vsl = Int(d.u16(vo + 4))
                    guard vso >= 0, vso + vsl <= d.count else { continue }
                    if let v = String(data: d[vso..<(vso + vsl)], encoding: .utf8), !seen.contains(v) {
                        vals.append(v)
                    }
                }
                merged[k] = vals
            }
        }

        let dst = AppConstants.sharedDir + "/domain_merged.bin"
        guard !merged.isEmpty else {
            try? FileManager.default.removeItem(atPath: dst); return
        }

        let sortedKeys = merged.keys.sorted()
        var keyStrings = Data(), valStrings = Data()

        var keyStrMap: [String: (off: Int, len: Int)] = [:]
        for k in sortedKeys {
            let b = Array(k.utf8)
            keyStrMap[k] = (keyStrings.count, b.count)
            keyStrings.append(contentsOf: b)
        }
        var valStrMap: [String: (off: Int, len: Int)] = [:]
        for k in sortedKeys {
            for v in merged[k]! where valStrMap[v] == nil {
                let b = Array(v.utf8)
                valStrMap[v] = (valStrings.count, b.count)
                valStrings.append(contentsOf: b)
            }
        }

        var valIndex = Data()
        var valIdx = 0
        var keyEntries: [(strOff: Int, strLen: Int, valStart: Int, valCount: Int)] = []
        for k in sortedKeys {
            let vals = merged[k]!
            let ks = keyStrMap[k]!
            keyEntries.append((ks.off, ks.len, valIdx, vals.count))
            for v in vals {
                let vs = valStrMap[v]!
                valIndex.appendU32(UInt32(vs.off))
                valIndex.appendU16(UInt16(vs.len))
                valIdx += 1
            }
        }

        var keyIndex = Data()
        for e in keyEntries {
            keyIndex.appendU32(UInt32(e.strOff))
            keyIndex.appendU16(UInt16(e.strLen))
            keyIndex.appendU32(UInt32(e.valStart))
            keyIndex.appendU16(UInt16(e.valCount))
        }

        let headerSize = 16
        let keyIndexOff = headerSize
        let valIndexOff = keyIndexOff + keyIndex.count
        let keyStrOff = valIndexOff + valIndex.count
        let valStrOff = keyStrOff + keyStrings.count

        var fixedKeyIndex = Data()
        for e in keyEntries {
            fixedKeyIndex.appendU32(UInt32(keyStrOff + e.strOff))
            fixedKeyIndex.appendU16(UInt16(e.strLen))
            fixedKeyIndex.appendU32(UInt32(e.valStart))
            fixedKeyIndex.appendU16(UInt16(e.valCount))
        }
        var fixedValIndex = Data()
        for k in sortedKeys {
            for v in merged[k]! {
                let vs = valStrMap[v]!
                fixedValIndex.appendU32(UInt32(valStrOff + vs.off))
                fixedValIndex.appendU16(UInt16(vs.len))
            }
        }

        var out = Data()
        out.append(contentsOf: [0x57, 0x42, 0x4D, 0x4D])
        out.appendU32(UInt32(sortedKeys.count))
        out.appendU32(UInt32(keyIndexOff))
        out.appendU32(UInt32(valIndexOff))
        out.append(fixedKeyIndex)
        out.append(fixedValIndex)
        out.append(keyStrings)
        out.append(valStrings)

        try? FileManager.default.createDirectory(atPath: AppConstants.sharedDir, withIntermediateDirectories: true)
        do {
            try out.write(to: URL(fileURLWithPath: dst))
            NSLog("DomainMerger: wrote %d keys, %d bytes", sortedKeys.count, out.count)
        } catch {
            NSLog("DomainMerger: write failed: %@", error.localizedDescription)
        }
    }
}

private extension Data {
    mutating func appendU32(_ v: UInt32) { var x = v.littleEndian; Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) } }
    mutating func appendU16(_ v: UInt16) { var x = v.littleEndian; Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) } }
}
