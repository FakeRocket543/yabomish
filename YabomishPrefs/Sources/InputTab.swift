import SwiftUI


private struct InputOption: Identifiable {
    let id: String
    let label: String
    let icon: String
    let desc: String
}

private let inputOptions: [InputOption] = {
    [
    .init(id: "autoCommit",           label: "自動送字",  icon: "arrow.right.circle",    desc: "滿碼自動送出"),
    .init(id: "showCodeHint",         label: "拆碼提示",  icon: "eye",                   desc: "送字後顯示碼"),
    .init(id: "homophoneMultiReading",label: "同音多讀",  icon: "speaker.wave.2",        desc: "含罕見讀音"),
    .init(id: "homophoneAutoExit",    label: "同音字選後自動退出", icon: "arrow.turn.up.left",  desc: "選字後退出模式"),
    .init(id: "fuzzyMatch",           label: "鄰鍵容錯",  icon: "magnifyingglass",       desc: "打錯相鄰鍵時自動容錯修正"),
    .init(id: "punctuationPairing",   label: "標點配對",  icon: "quote.opening",         desc: "打「自動補「」"),
    ]
}()

struct InputTab: View {
    @Bindable var store: PrefsStore
    @State private var importResult: ImportResult?
    @State private var cinImported = false
    @State private var cinSize: Int64 = 0
    @State private var showImportForm = false

    /// 匯入結果回饋（成功／失敗共用同一個 alert）
    struct ImportResult: Identifiable {
        let id = UUID()
        let success: Bool
        let message: String
    }

    var body: some View {
        SettingsPage {
                // CIN import — 已匯入時塌成一行狀態列
                if cinImported && !showImportForm {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Typo.success)
                        Text("已匯入 liu.cin（\(formatBytes(cinSize))）").font(Typo.body)
                        Spacer()
                        Button("重新匯入⋯") { showImportForm = true }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Typo.cardOff))
                } else {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("嘸蝦米字表（liu.cin）", systemImage: "doc.badge.arrow.up").font(Typo.h2)
                        Text("Yabomish 需要嘸蝦米的 .cin 字表檔才能運作。如果你有購買嘸蝦米輸入法，請從安裝目錄中找到 liu.cin，點擊下方按鈕匯入。字表僅在本機編譯使用，不會上傳。")
                            .font(Typo.body).foregroundStyle(.secondary)
                        HStack {
                            Button {
                                // FIX: .cin is not a system-recognized UTType.
                                // Using UTType(filenameExtension: "cin") caused .cin files
                                // to appear grayed-out / unselectable in NSOpenPanel.
                                // Solution: use broad types [.plainText, .data] + allowsOtherFileTypes.
                                NSApp.activate(ignoringOtherApps: true)
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.plainText, .data]
                                panel.allowsOtherFileTypes = true
                                panel.message = "選擇嘸蝦米字表（.cin）或擴充表（.txt）"
                                guard panel.runModal() == .OK, let url = panel.url else { return }
                                importTable(from: url)
                            } label: {
                                Label("匯入字表⋯", systemImage: "folder.badge.plus")
                            }
                            Spacer()
                        }
                    }
                    .padding(4)
                }
                }

                SettingsSection(title: "輸入功能") {
                    ForEach(Array(inputOptions.enumerated()), id: \.element.id) { i, opt in
                        if i > 0 { InsetDivider() }
                        ToggleRow(label: opt.label, icon: opt.icon, desc: opt.desc,
                                  on: binding(for: opt.id))
                    }
                }

                // ── Shift+數字鍵輸出 ──
                #if !MINIMAL
                SettingsSection(title: "Shift＋數字鍵（候選顯示時）",
                                footnote: "候選字／聯想顯示中，按住 Shift 再按數字列的輸出。閒置狀態恆為符號；組字中 Shift+8 萬用碼不受影響。") {
                    ChoiceRow(label: "符號 !@#$%", icon: "exclamationmark",
                              desc: "全系統慣例（預設）",
                              selected: store.shiftDigitOutput == "symbol") { store.shiftDigitOutput = "symbol" }
                    InsetDivider()
                    ChoiceRow(label: "數字 12345", icon: "number",
                              desc: "候選顯示時快速輸入數字",
                              selected: store.shiftDigitOutput == "digit") { store.shiftDigitOutput = "digit" }
                }
                #endif

                // ── 固定排序 ──
                DisclosureGroup {
                    PinnedOrderSection()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("固定同碼字排序").font(.system(size: 13, weight: .semibold))
                        Text("指定某碼的候選字固定順序，不受學習排序影響。")
                            .font(Typo.caption).foregroundStyle(.secondary)
                    }
                }

                // ── 查字歷史 ──
                DisclosureGroup {
                    LookupHistorySection()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("查字歷史").font(.system(size: 13, weight: .semibold))
                        Text("反查模式（注音／同音／拼音）選字送出的自動記錄——就是「不會拆碼的字」清單，可匯出複習。")
                            .font(Typo.caption).foregroundStyle(.secondary)
                    }
                }

        }
        .onAppear { refreshCinState() }
        .alert(importResult?.success == true ? "字表匯入成功" : "匯入失敗",
               isPresented: Binding(
                   get: { importResult != nil },
                   set: { if !$0 { importResult = nil } }
               )) {
            Button("好") { importResult = nil }
        } message: {
            Text(importResult?.message ?? "")
        }
    }

    // MARK: - CIN 狀態

    /// 檢查 sharedDir/liu.cin 是否存在且非空；成功匯入後同步更新
    private func refreshCinState() {
        let path = sharedDir + "/liu.cin"
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
        cinImported = size > 0
        cinSize = size
        if cinImported { showImportForm = false }
    }

    private func formatBytes(_ n: Int64) -> String {
        if n >= 1_048_576 { return String(format: "%.1f MB", Double(n) / 1_048_576.0) }
        if n >= 1024 { return String(format: "%.0f KB", Double(n) / 1024.0) }
        return "\(n) 位元組"
    }

    /// 匯入字表／擴充表：寫入輸入法實際讀取的正規路徑（與 AppConstants.sharedDir 一致）：
    /// 主表固定為 ~/Library/Application Support/Yabomish/liu.cin（IM 只認這個檔名），
    /// 擴充表放入 tables/ 保留原檔名（CINTable.loadExtras 逐一把 *.txt 疊加上去）。
    private func importTable(from url: URL) {
        switch url.pathExtension.lowercased() {
        case "cin":
            importFile(from: url, to: sharedDir + "/liu.cin", clearCompiledCache: true)
        case "txt":
            importFile(from: url, to: sharedDir + "/tables/" + url.lastPathComponent, clearCompiledCache: false)
        default:
            importResult = ImportResult(success: false,
                                        message: "不支援的檔案類型「.\(url.pathExtension)」。\n請選擇 .cin 主字表或 .txt 擴充表。")
        }
    }

    private func importFile(from src: URL, to dest: String, clearCompiledCache: Bool) {
        let fm = FileManager.default
        do {
            // 來源驗證：存在且非空
            let srcSize = (try fm.attributesOfItem(atPath: src.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard srcSize > 0 else {
                importResult = ImportResult(success: false, message: "檔案是空的：\(src.lastPathComponent)")
                return
            }
            // .cin 內容嗅探：正規 .cin 必含 %chardef 段（只讀前 64KB）
            if clearCompiledCache {
                let head: String = {
                    guard let fh = try? FileHandle(forReadingFrom: src),
                          let data = try? fh.read(upToCount: 65536) else { return "" }
                    try? fh.close()
                    return String(decoding: data, as: UTF8.self)
                }()
                guard head.contains("%chardef") else {
                    importResult = ImportResult(success: false,
                                                message: "這不像正規 .cin 字表（找不到 %chardef 段）：\n\(src.lastPathComponent)")
                    return
                }
            }
            try fm.createDirectory(atPath: (dest as NSString).deletingLastPathComponent,
                                   withIntermediateDirectories: true)
            // 原子替換：先拷到同目錄暫存檔再取代，失敗不會弄丟舊表
            let tmp = dest + ".tmp-\(UUID().uuidString.prefix(8))"
            defer { try? fm.removeItem(atPath: tmp) }  // 成功時已搬走，此為失敗殘留清理
            try fm.copyItem(atPath: src.path, toPath: tmp)
            let destURL = URL(fileURLWithPath: dest)
            if fm.fileExists(atPath: dest) {
                _ = try fm.replaceItemAt(destURL, withItemAt: URL(fileURLWithPath: tmp))
            } else {
                try fm.moveItem(atPath: tmp, toPath: dest)
            }
            // 清除輸入法真正的編譯快取（liu.bin）；reload 端另有 mtime 檢查雙保險
            if clearCompiledCache { try? fm.removeItem(atPath: sharedDir + "/liu.bin") }
            // 目的地驗證：存在且非空
            let destSize = (try? fm.attributesOfItem(atPath: dest)[.size] as? NSNumber)?.int64Value ?? 0
            guard fm.fileExists(atPath: dest), destSize > 0 else {
                importResult = ImportResult(success: false, message: "複製後驗證失敗：\n\(dest)")
                return
            }
            // 通知輸入法即時重載（AppDelegate 監聽 com.yabomish.reloadTables）
            DistributedNotificationCenter.default().post(name: .init("com.yabomish.reloadTables"), object: nil)
            if clearCompiledCache { refreshCinState() }
            importResult = ImportResult(success: true,
                                        message: "已匯入 \(src.lastPathComponent)（\(destSize) 位元組）→\n\(dest)\n輸入法已收到重載通知。")
        } catch {
            importResult = ImportResult(success: false, message: error.localizedDescription)
        }
    }

    /// 正規資料目錄：~/Library/Application Support/<dataDirName>
    /// （stable=Yabomish、dev=YabomishDev —— 依 PrefsStore 的 suite 區分，
    ///  dev 設定程式匯入字表不會寫到 stable 目錄）
    private var sharedDir: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(store.dataDirName, isDirectory: true).path
    }

    private func binding(for key: String) -> Binding<Bool> {
        switch key {
        case "autoCommit":            return $store.autoCommit
        case "showCodeHint":          return $store.showCodeHint
        case "homophoneMultiReading": return $store.homophoneMultiReading
        case "homophoneAutoExit":     return $store.homophoneAutoExit
        case "fuzzyMatch":            return $store.fuzzyMatch
        case "punctuationPairing":    return $store.punctuationPairing
        case "allowSecureInput":      return $store.allowSecureInput
        default:                      return .constant(false)
        }
    }
}
