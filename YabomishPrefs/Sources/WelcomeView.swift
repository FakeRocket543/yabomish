import SwiftUI

struct WelcomeView: View {
    @State private var page = 0
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomePage(
                    icon: "doc.text",
                    title: "匯入字表",
                    lines: [
                        "首次使用需要匯入嘸蝦米字表（liu.cin）。",
                        "切換到 Yabomish 時會自動引導匯入，",
                        "或將 liu.cin 放到 ~/Library/YabomishIM/",
                    ]
                ).tag(0)

                welcomePage(
                    icon: "keyboard",
                    title: "加入輸入方式",
                    lines: [
                        "系統設定 → 鍵盤 → 輸入方式",
                        "點「+」→ 找到「繁體中文」→「Yabomish」",
                        "加入後即可從狀態列切換使用。",
                    ]
                ).tag(1)

                welcomePage(
                    icon: "command",
                    title: "常用快捷鍵",
                    lines: [
                        "Shift 單擊　　切換中／英文",
                        "';　　　　　　注音反查模式",
                        "Shift+Space　全形空白",
                        "Shift+*　　　萬用字元",
                        "Tab / 方向鍵　翻頁選字",
                    ]
                ).tag(2)
            }
            .tabViewStyle(.automatic)

            Divider()
            HStack {
                if page > 0 {
                    Button("上一步") { withAnimation { page -= 1 } }
                }
                Spacer()
                // 頁碼指示
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if page < 2 {
                    Button("下一步") { withAnimation { page += 1 } }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("開始使用") { onDone() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 460, height: 340)
    }

    @ViewBuilder
    private func welcomePage(icon: String, title: String, lines: [String]) -> some View {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
