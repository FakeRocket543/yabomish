import SwiftUI

struct ContentView: View {
    @Bindable var store: PrefsStore

    var body: some View {
        if store.hasSeenWelcome {
            mainView
        } else {
            WelcomeView { store.hasSeenWelcome = true }
        }
    }

    private var mainView: some View {
        TabView {
            InputTab(store: store).tabItem { Label("輸入", systemImage: "keyboard") }
            SuggestionTab(store: store).tabItem { Label("聯想與詞庫", systemImage: "text.magnifyingglass") }
            ShortcutTab().tabItem { Label("短碼", systemImage: "text.cursor") }
            AppearanceTab(store: store).tabItem { Label("外觀", systemImage: "paintbrush") }
            HelpTab().tabItem { Label("關於", systemImage: "info.circle") }
        }
        .frame(minWidth: 640, minHeight: 520)
    }
}
