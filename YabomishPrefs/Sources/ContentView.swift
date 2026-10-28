import SwiftUI

extension Notification.Name {
    /// View menu Cmd+1..5 切換頂層分頁（main.swift 的 selectTab 發送，object 為 Int index）
    static let selectPrefsTab = Notification.Name("com.yabomish.selectPrefsTab")
}

struct ContentView: View {
    @Bindable var store: PrefsStore
    @State private var selection: Int? = 0

    private var colorScheme: ColorScheme? {
        switch store.appearanceMode {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some View {
        Group {
            if store.hasSeenWelcome {
                mainView
            } else {
                WelcomeView { store.hasSeenWelcome = true }
            }
        }
        .preferredColorScheme(colorScheme)
    }

    // 系統設定式格局：側邊欄分頁 + 右側置中限寬內容（SettingsPage）
    private var mainView: some View {
        NavigationSplitView {
            List(selection: $selection) {
                sidebarItem("輸入", icon: "keyboard", color: .blue).tag(0)
                #if !MINIMAL
                sidebarItem("聯想與詞庫", icon: "text.magnifyingglass", color: .purple).tag(1)
                sidebarItem("快捷碼", icon: "text.cursor", color: .orange).tag(2)
                sidebarItem("外觀", icon: "paintbrush", color: .pink).tag(3)
                sidebarItem("關於", icon: "info.circle", color: .gray).tag(4)
                #else
                sidebarItem("快捷碼", icon: "text.cursor", color: .orange).tag(1)
                sidebarItem("外觀", icon: "paintbrush", color: .pink).tag(2)
                sidebarItem("關於", icon: "info.circle", color: .gray).tag(3)
                #endif
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            detailView(for: selection ?? 0)
        }
        .frame(minWidth: 920, minHeight: 600)
        .onAppear { clampSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .selectPrefsTab)) { note in
            if let idx = note.object as? Int { selection = idx; clampSelection() }
        }
    }

    /// 側邊欄項目：系統設定式彩色圓角圖示＋標題
    private func sidebarItem(_ title: String, icon: String, color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(color))
        }
    }

    @ViewBuilder
    private func detailView(for tag: Int) -> some View {
        #if !MINIMAL
        switch tag {
        case 0: InputTab(store: store)
        case 1: SuggestionTab(store: store)
        case 2: ShortcutTab()
        case 3: AppearanceTab(store: store)
        default: HelpTab()
        }
        #else
        switch tag {
        case 0: InputTab(store: store)
        case 1: ShortcutTab()
        case 2: AppearanceTab(store: store)
        default: HelpTab()
        }
        #endif
    }

    /// MINIMAL 版少一個分頁：selection 越界時夾回合法範圍
    private func clampSelection() {
        #if MINIMAL
        let maxTag = 3
        #else
        let maxTag = 4
        #endif
        if (selection ?? 0) > maxTag { selection = 0 }
    }
}
