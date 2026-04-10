import SwiftUI

struct SuggestionTab: View {
    @Bindable var store: PrefsStore

    var body: some View {
        Form {
            Picker("策略", selection: $store.suggestStrategy) {
                Text("一般優先（詞→詞庫→字）").tag("general")
                Text("專業優先（詞庫→詞→字）").tag("domain")
                Text("字級優先（字→詞→詞庫）").tag("char")
            }
            Picker("詞級語料", selection: $store.wordCorpus) {
                Text("萌典詞組").tag("moedict")
                Text("維基斷詞").tag("wiki")
                Text("台灣新聞斷詞").tag("news")
            }
            Toggle("字級聯想（bigram、trigram）", isOn: $store.charSuggest)
        }
        .padding()
    }
}
