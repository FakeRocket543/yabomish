import SwiftUI

struct ContentView: View {
    @Bindable var store: PrefsStore

    var body: some View {
        TabView {
            InputTab(store: store).tabItem { Label("輸入", systemImage: "keyboard") }
            SuggestionTab(store: store).tabItem { Label("聯想", systemImage: "text.magnifyingglass") }
            DomainTab(store: store).tabItem { Label("詞庫", systemImage: "books.vertical") }
            AppearanceTab(store: store).tabItem { Label("外觀", systemImage: "paintbrush") }
        }
        .frame(minWidth: 560, minHeight: 400)
    }
}
