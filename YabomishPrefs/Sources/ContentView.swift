import SwiftUI

extension Notification.Name {
    /// View menu Cmd+1..5 切換頂層 tab（main.swift 的 selectTab 發送，object 為 Int index）
    static let selectPrefsTab = Notification.Name("com.yabomish.selectPrefsTab")
}

struct ContentView: View {
    @Bindable var store: PrefsStore
    @State private var selection = 0

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

    private var mainView: some View {
        TabView(selection: $selection) {
            InputTab(store: store).tabItem { Label("輸入", systemImage: "keyboard") }.tag(0)
            #if !MINIMAL
            SuggestionTab(store: store).tabItem { Label("聯想與詞庫", systemImage: "text.magnifyingglass") }.tag(1)
            ShortcutTab().tabItem { Label("快捷碼", systemImage: "text.cursor") }.tag(2)
            AppearanceTab(store: store).tabItem { Label("外觀", systemImage: "paintbrush") }.tag(3)
            HelpTab().tabItem { Label("關於", systemImage: "info.circle") }.tag(4)
            #else
            ShortcutTab().tabItem { Label("快捷碼", systemImage: "text.cursor") }.tag(1)
            AppearanceTab(store: store).tabItem { Label("外觀", systemImage: "paintbrush") }.tag(2)
            HelpTab().tabItem { Label("關於", systemImage: "info.circle") }.tag(3)
            #endif
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear { clampSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .selectPrefsTab)) { note in
            if let idx = note.object as? Int { selection = idx; clampSelection() }
        }
    }

    /// MINIMAL 版少一個 tab：selection 越界時夾回合法範圍
    private func clampSelection() {
        #if MINIMAL
        let maxTag = 3
        #else
        let maxTag = 4
        #endif
        if selection > maxTag { selection = 0 }
    }
}
