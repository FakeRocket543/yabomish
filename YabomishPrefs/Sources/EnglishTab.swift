import SwiftUI

/// 英數輸入設定：英文聯想開關 + 自訂詞管理。
/// 移植自 yabomish iOS 版——英文模式下字母攔截為組字、候選窗顯示補全。
struct EnglishTab: View {
    @Bindable var store: PrefsStore
    @State private var words: [String] = []
    @State private var showClearConfirm = false

    private var dict: UserEnglishDict {
        UserEnglishDict(dir: appSupportDir)
    }

    private var appSupportDir: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(store.dataDirName, isDirectory: true).path
    }

    var body: some View {
        SettingsPage {
            SettingsSection(title: "英文聯想",
                            footnote: "英文模式打字時，候選窗即時顯示單字補全（約 1 萬常用詞＋你的自訂詞）；數字鍵或點選送字。沒有匹配且打滿 3 個字母時，候選列出現「＋前綴」可把新詞加入自訂詞。密碼欄位不啟用。") {
                ToggleRow(label: "英文聯想輸入", icon: "textformat.abc",
                          desc: "英文模式顯示單字補全（預設開）",
                          on: $store.englishSuggest)
            }

            SettingsSection(title: "自訂詞（\(words.count)）",
                            footnote: "英文模式下選擇「＋前綴」候選時自動收錄。此處可刪除或清空。") {
                if words.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "tray").foregroundStyle(.secondary)
                        Text("尚無自訂詞").font(Typo.body).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                } else {
                    ForEach(Array(words.enumerated()), id: \.element) { i, word in
                        if i > 0 { InsetDivider() }
                        HStack {
                            Text(word).font(Typo.body)
                            Spacer()
                            Button {
                                dict.remove(word)
                                reload()
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                    InsetDivider()
                    HStack {
                        Spacer()
                        Button("全部清空⋯") { showClearConfirm = true }
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
            }
        }
        .onAppear { reload() }
        .alert("清空全部自訂詞？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { dict.removeAll(); reload() }
        }
    }

    private func reload() { words = dict.allWords }
}
