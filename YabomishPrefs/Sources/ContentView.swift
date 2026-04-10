import SwiftUI

struct ContentView: View {
    @Bindable var store: PrefsStore

    var body: some View {
        TabView {
            SuggestionTab(store: store).tabItem { Text("聯想設定") }
            DomainTab(store: store).tabItem { Text("詞庫") }
            AppearanceTab(store: store).tabItem { Text("外觀") }
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
