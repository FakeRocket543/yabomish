import SwiftUI

struct ContentView: View {
    @Bindable var store: PrefsStore

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
        TabView {
            InputTab(store: store).tabItem { Label("輸入", systemImage: "keyboard") }
            #if !MINIMAL
            SuggestionTab(store: store).tabItem { Label("聯想與詞庫", systemImage: "text.magnifyingglass") }
            #endif
            ShortcutTab().tabItem { Label("快捷碼", systemImage: "text.cursor") }
            AppearanceTab(store: store).tabItem { Label("外觀", systemImage: "paintbrush") }
            HelpTab().tabItem { Label("關於", systemImage: "info.circle") }
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}
