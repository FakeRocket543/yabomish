import SwiftUI

struct SuggestionTab: View {
    @Bindable var store: PrefsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("聯想策略") {
                    VStack(alignment: .leading, spacing: 10) {
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
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("字級聯想") {
                    Toggle("啟用 bigram、trigram 字級聯想", isOn: $store.charSuggest)
                        .padding(.vertical, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
