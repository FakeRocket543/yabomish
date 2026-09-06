import SwiftUI
import SQLite3
import UniformTypeIdentifiers

/// 查字歷史檢視：直接唯讀 freq.db 的 lookup_history 表（與 macOS 29eb2c2 功能對應的 GUI 版）。
/// 提供檢視、匯出 CSV、清除；不參與任何排序邏輯。
struct LookupHistorySection: View {
    struct Entry: Identifiable {
        let id: Int64
        let ts: Double
        let mode: String
        let query: String
        let char: String
        let code: String

        var modeLabel: String {
            switch mode {
            case "zh": return "注音"
            case "to": return "同音"
            case "pys": return "拼(簡)"
            case "pyt": return "拼(繁)"
            default: return mode
            }
        }

        /// 每列顯示都用到的格式：static 快取，避免上千筆記錄各建一個 formatter
        private static let listTime: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "MM/dd HH:mm"
            return f
        }()

        var timeText: String {
            Self.listTime.string(from: Date(timeIntervalSince1970: ts))
        }
    }

    @State private var entries: [Entry] = []
    @State private var showClearConfirm = false
    @State private var exportedPath: String?

    private static let dbPath: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Yabomish/freq.db").path
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entries.isEmpty ? "尚無記錄" : "共 \(entries.count) 筆（新→舊）")
                    .font(Typo.caption).foregroundStyle(.secondary)
                Spacer()
                Button("匯出 CSV") { exportCSV() }
                    .disabled(entries.isEmpty)
                Button("全部清除", role: .destructive) { showClearConfirm = true }
                    .disabled(entries.isEmpty)
            }

            if entries.isEmpty {
                Text("在輸入法裡用 ,,ZH／,,TO／,,PYS／,,PYT 反查並選字後，會自動記錄在這裡（上限 1000 筆）。")
                    .font(Typo.hint).foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(entries) { e in
                            HStack(spacing: 10) {
                                Text(e.char).font(.system(size: 17))
                                    .frame(width: 28, alignment: .center)
                                Text(e.code).font(Typo.bodyMono).foregroundStyle(Typo.accent)
                                if !e.query.isEmpty {
                                    Text("←\(e.query)").font(Typo.caption).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(e.modeLabel).font(Typo.cardBadge).foregroundStyle(.secondary)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.06)).cornerRadius(4)
                                Text(e.timeText).font(Typo.cardBadge).foregroundStyle(.tertiary)
                                    .frame(width: 78, alignment: .trailing)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .frame(maxHeight: 264)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12), lineWidth: 1))

                if let path = exportedPath {
                    Text("已匯出：\(path)").font(Typo.caption).foregroundStyle(Typo.success)
                        .textSelection(.enabled)
                }
            }
        }
        .onAppear { reload() }
        .confirmationDialog("清除全部查字歷史？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清除 \(entries.count) 筆記錄", role: .destructive) {
                clearAll()
            }
        } message: {
            Text("此操作不可復原。字頻學習資料不受影響（,,RS 只重置字頻、,,RH 只清查字歷史）。")
        }
    }

    // MARK: - Actions

    private func reload() {
        entries = Self.readEntries()
    }

    private func clearAll() {
        var db: OpaquePointer?
        guard sqlite3_open(Self.dbPath, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "DELETE FROM lookup_history", nil, nil, nil)
        entries = []
        exportedPath = nil
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmm"
            return "查字歷史-\(f.string(from: Date())).csv"
        }()
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var lines = ["時間,模式,查詢,字,嘸蝦米碼"]
        for e in entries {
            let time = f.string(from: Date(timeIntervalSince1970: e.ts))
            lines.append("\(csvEscape(time)),\(csvEscape(e.mode)),\(csvEscape(e.query)),\(csvEscape(e.char)),\(csvEscape(e.code))")
        }
        // UTF-8 BOM：讓 Excel 直接開啟中文不亂碼
        let text = "\u{FEFF}" + lines.joined(separator: "\n") + "\n"
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportedPath = url.path
        } catch {
            exportedPath = nil
        }
    }

    // MARK: - SQLite（唯讀）

    private static func readEntries() -> [Entry] {
        var out: [Entry] = []
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return out }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        // WAL 下讀取輸入法正在寫的同一個 DB：唯讀連線安全
        guard sqlite3_prepare_v2(db, "SELECT id, ts, mode, query, char, code FROM lookup_history ORDER BY id DESC LIMIT 1000", -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(Entry(
                id: sqlite3_column_int64(stmt, 0),
                ts: sqlite3_column_double(stmt, 1),
                mode: String(cString: sqlite3_column_text(stmt, 2)),
                query: String(cString: sqlite3_column_text(stmt, 3)),
                char: String(cString: sqlite3_column_text(stmt, 4)),
                code: String(cString: sqlite3_column_text(stmt, 5))))
        }
        return out
    }
}
