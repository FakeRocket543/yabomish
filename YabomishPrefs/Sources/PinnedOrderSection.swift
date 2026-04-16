import SwiftUI
import SQLite3

struct PinnedOrderSection: View {
    @State private var code = ""
    @State private var candidates: [String] = []
    @State private var pinned: [String] = []
    @State private var allPinned: [(code: String, chars: String)] = []

    private static let dbPath: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Yabomish/freq.db").path
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Input code
            HStack {
                TextField("輸入碼（如 a）", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .font(Typo.bodyMono)
                    .onSubmit { lookup() }
                Button("查詢") { lookup() }
                    .disabled(code.isEmpty)
            }

            // Candidates + pinned reorder
            if !candidates.isEmpty {
                HStack(alignment: .top, spacing: 16) {
                    // Left: available candidates
                    VStack(alignment: .leading, spacing: 4) {
                        Text("候選字").font(Typo.caption).foregroundStyle(.secondary)
                        ForEach(candidates, id: \.self) { ch in
                            Button {
                                if !pinned.contains(ch) { pinned.append(ch) }
                            } label: {
                                HStack {
                                    Text(ch).font(.system(size: 18))
                                    Spacer()
                                    if pinned.contains(ch) {
                                        Image(systemName: "checkmark").foregroundStyle(Typo.cyan)
                                    } else {
                                        Image(systemName: "plus.circle").foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(pinned.contains(ch) ? Typo.cyan.opacity(0.1) : Color.clear)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 120)

                    // Right: pinned order
                    if !pinned.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("固定順序（上→下）").font(Typo.caption).foregroundStyle(.secondary)
                            ForEach(Array(pinned.enumerated()), id: \.offset) { i, ch in
                                HStack(spacing: 6) {
                                    Text("\(i + 1).").font(Typo.caption).foregroundStyle(.tertiary).frame(width: 16)
                                    Text(ch).font(.system(size: 18))
                                    Spacer()
                                    Button { if i > 0 { pinned.swapAt(i, i - 1) } } label: {
                                        Image(systemName: "chevron.up").font(.caption)
                                    }.disabled(i == 0).buttonStyle(.borderless)
                                    Button { if i < pinned.count - 1 { pinned.swapAt(i, i + 1) } } label: {
                                        Image(systemName: "chevron.down").font(.caption)
                                    }.disabled(i == pinned.count - 1).buttonStyle(.borderless)
                                    Button { pinned.remove(at: i) } label: {
                                        Image(systemName: "xmark").font(.caption).foregroundStyle(.red)
                                    }.buttonStyle(.borderless)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Typo.gold.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                        .frame(width: 180)
                    }
                }

                HStack {
                    Button("儲存") { save(); loadAll() }
                        .disabled(pinned.isEmpty)
                    if !pinned.isEmpty {
                        Button("清除此碼") { pinned = []; delete(); loadAll() }
                    }
                }
            }

            // Existing pinned list
            if !allPinned.isEmpty {
                Divider()
                Text("已固定的碼").font(Typo.caption).foregroundStyle(.secondary)
                ForEach(allPinned, id: \.code) { item in
                    HStack {
                        Text(item.code).font(Typo.bodyMono).frame(width: 50, alignment: .leading)
                        Text("→").foregroundStyle(.tertiary)
                        Text(item.chars).font(.system(size: 16))
                        Spacer()
                        Button {
                            deleteCode(item.code); loadAll()
                        } label: {
                            Image(systemName: "trash").font(.caption).foregroundStyle(.red)
                        }.buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { code = item.code; lookup() }
                }
            }
        }
        .onAppear { loadAll() }
    }

    // MARK: - CIN lookup

    private func lookup() {
        let c = code.lowercased().trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return }
        candidates = cinLookup(c)
        pinned = loadPinned(c) ?? []
    }

    private func cinLookup(_ code: String) -> [String] {
        let paths = [
            "/Library/Input Methods/YabomishIM.app/Contents/Resources/liu.bin",
            NSHomeDirectory() + "/Library/Application Support/Yabomish/liu.bin",
            NSHomeDirectory() + "/Library/YabomishIM/liu.bin",
        ]
        guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              data.count >= 128,
              data[0] == 0x43, data[1] == 0x49, data[2] == 0x4E, data[3] == 0x4D
        else { return [] }
        let entryCount = Int(data.u32(4))
        let codesOff = Int(data.u32(96))
        let valsOff = Int(data.u32(100))
        let stringsOff = Int(data.u32(104))
        let charsOff = Int(data.u32(108))
        let codeBytes = Array(code.utf8)
        // Binary search
        var lo = 0, hi = entryCount - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let eo = codesOff + mid * 6
            guard eo + 6 <= data.count else { break }
            let so = stringsOff + Int(data.u32(eo))
            let sl = Int(data.u16(eo + 4))
            guard so + sl <= data.count else { break }
            let key = Array(data[so..<so+sl])
            if key == codeBytes {
                // Read chars from vals
                let ve = valsOff + mid * 4
                guard ve + 3 <= data.count else { return [] }
                let vOff = Int(data.u16(ve))
                let vCnt = Int(data[ve + 2])
                var result: [String] = []
                for j in 0..<vCnt {
                    let off = charsOff + (vOff + j) * 4
                    guard off + 4 <= data.count else { break }
                    let cp = data.u32(off)
                    if let s = Unicode.Scalar(cp) { result.append(String(s)) }
                }
                return result
            }
            if key.lexicographicallyPrecedes(codeBytes) { lo = mid + 1 } else { hi = mid - 1 }
        }
        return []
    }

    // MARK: - SQLite

    private func loadPinned(_ code: String) -> [String]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(Self.dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT chars FROM pinned WHERE code=?1", -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, code, -1, SQLITE_TRANSIENT_)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let chars = String(cString: sqlite3_column_text(stmt, 0))
        return Array(chars).map(String.init)
    }

    private func save() {
        let c = code.lowercased().trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty, !pinned.isEmpty else { return }
        var db: OpaquePointer?
        guard sqlite3_open(Self.dbPath, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS pinned(code TEXT PRIMARY KEY, chars TEXT NOT NULL)", nil, nil, nil)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO pinned(code,chars) VALUES(?1,?2)", -1, &stmt, nil) == SQLITE_OK else { return }
        let joined = pinned.joined()
        sqlite3_bind_text(stmt, 1, c, -1, SQLITE_TRANSIENT_)
        sqlite3_bind_text(stmt, 2, joined, -1, SQLITE_TRANSIENT_)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        notifyIM()
    }

    private func delete() {
        let c = code.lowercased().trimmingCharacters(in: .whitespaces)
        deleteCode(c)
    }

    private func deleteCode(_ c: String) {
        var db: OpaquePointer?
        guard sqlite3_open(Self.dbPath, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM pinned WHERE code=?1", -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, c, -1, SQLITE_TRANSIENT_)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        notifyIM()
    }

    private func loadAll() {
        var db: OpaquePointer?
        guard sqlite3_open_v2(Self.dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { allPinned = []; return }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT code, chars FROM pinned ORDER BY code", -1, &stmt, nil) == SQLITE_OK else { allPinned = []; return }
        var result: [(code: String, chars: String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let code = String(cString: sqlite3_column_text(stmt, 0))
            let chars = String(cString: sqlite3_column_text(stmt, 1))
            result.append((code: code, chars: chars))
        }
        sqlite3_finalize(stmt)
        allPinned = result
    }

    private func notifyIM() {
        DistributedNotificationCenter.default().post(name: .init("com.yabomish.prefsChanged"), object: nil)
    }
}

private let SQLITE_TRANSIENT_ = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension Data {
    func u32(_ offset: Int) -> UInt32 {
        withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
    }
    func u16(_ offset: Int) -> UInt16 {
        withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self) }
    }
}
