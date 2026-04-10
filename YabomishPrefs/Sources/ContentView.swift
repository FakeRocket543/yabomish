import SwiftUI

struct ContentView: View {
    @Bindable var store: PrefsStore

    var body: some View {
        TabView {
            InputTab(store: store).tabItem { Label("輸入 / 選字窗", systemImage: "keyboard") }
            SuggestionTab(store: store).tabItem { Label("聯想設定", systemImage: "text.magnifyingglass") }
            DomainTab(store: store).tabItem { Label("詞庫", systemImage: "books.vertical") }
            AppearanceTab(store: store).tabItem { Label("外觀", systemImage: "paintbrush") }
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
