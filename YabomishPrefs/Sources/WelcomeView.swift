import SwiftUI

struct WelcomeView: View {
    @State private var page = 0
    @State private var cinExists = false
    var onDone: () -> Void

    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            // macOS 無 iOS 式 paging dots：TabView(.automatic) 只剩空白頂欄，
            // 改 ZStack/if 切頁＋手刻 dots
            ZStack {
                if page == 0 {
                    welcomePage(
                        icon: "doc.text",
                        title: "匯入字表",
                        lines: [
                            "首次使用需要匯入嘸蝦米字表（liu.cin）。",
                            "切換到 Yabomish 時會自動引導匯入。",
                        ],
                        status: cinExists ? "✓ 已偵測到 liu.cin，可直接開始使用" : nil
                    )
                } else if page == 1 {
                    welcomePage(
                        icon: "arrow.counterclockwise.circle",
                        title: "登出再登入",
                        lines: [
                            "安裝完成後，請先登出再登入，",
                            "讓系統重新載入輸入法清單。",
                            "（僅首次安裝需要，之後更新不用）",
                        ]
                    )
                } else if page == 2 {
                    welcomePage(
                        icon: "keyboard",
                        title: "加入輸入方式",
                        lines: [
                            "系統設定 → 鍵盤 → 輸入方式",
                            "點「+」→ 找到「繁體中文」→「Yabomish」",
                            "加入後即可從狀態列切換使用。",
                        ]
                    )
                } else {
                    welcomePage(
                        icon: "command",
                        title: "常用快捷鍵",
                        lines: [
                            "Shift 單擊　　切換中／英文",
                            ",,ZH　　　　　注音反查模式",
                            "Shift+Space　全形空白",
                            "Shift+*　　　萬用字元",
                            "Tab / 方向鍵　翻頁選字",
                        ]
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                Button("略過") { onDone() }
                    .foregroundStyle(.secondary)
                if page > 0 {
                    Button("上一步") { withAnimation { page -= 1 } }
                }
                Spacer()
                // 頁碼指示
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Circle()
                            .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if page < pageCount - 1 {
                    Button("下一步") { withAnimation { page += 1 } }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("開始使用") { onDone() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(minWidth: 460, minHeight: 340)
        .padding(12)
        .onAppear { detectCin() }
    }

    /// 第一頁偵測 liu.cin 是否已存在（存在即顯示狀態，不再催匯入）
    private func detectCin() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let path = dir.appendingPathComponent("Yabomish/liu.cin").path
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
        cinExists = size > 0
    }

    @ViewBuilder
    private func welcomePage(icon: String, title: String, lines: [String], status: String? = nil) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.self) { line in
                    Text(line).font(.body)
                }
            }
            .frame(maxWidth: 340)
            if let status {
                Text(status).font(.body).foregroundStyle(Color.green)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
