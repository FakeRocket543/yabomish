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
                Label("輸入", systemImage: "keyboard").tag(0)
                #if !MINIMAL
                Label("聯想與詞庫", systemImage: "text.magnifyingglass").tag(1)
                Label("快捷碼", systemImage: "text.cursor").tag(2)
                Label("外觀", systemImage: "paintbrush").tag(3)
                Label("關於", systemImage: "info.circle").tag(4)
                #else
                Label("快捷碼", systemImage: "text.cursor").tag(1)
                Label("外觀", systemImage: "paintbrush").tag(2)
                Label("關於", systemImage: "info.circle").tag(3)
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
