import SwiftUI

struct HelpTab: View {
    @State private var helpText: String = ""
    @State private var helpQuery = ""
    @State private var collapsedGuides: Set<String> = []

    /// dev suite → YabomishDev（與 PrefsStore.dataDirName 同規則）
    private var dataDirName: String {
        (UserDefaults.standard.string(forKey: "prefsSuite") ?? "").contains("Dev")
            ? "YabomishDev" : "Yabomish"
    }

    /// 搜尋過濾：(haystack, value) 配對，query 為空全留
    private func helpHits<T>(_ pairs: [(String, T)]) -> [T] {
        let q = helpQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return pairs.map(\.1) }
        return pairs.filter { $0.0.localizedCaseInsensitiveContains(q) }.map(\.1)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜尋說明", text: $helpQuery)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            Divider()
        SettingsPage {

                // ── 共用說明文件 ──
                if !helpText.isEmpty {
                    if let attr = try? AttributedString(markdown: helpText) {
                        Text(attr)
                    } else {
                        Text(helpText)
                    }
                    SectionDivider()
                }

                // ── 使用方法 ──

                Label("使用方法", systemImage: "book").font(Typo.h1)

                guide("匯入字表", icon: "doc.badge.arrow.up", steps: [
                    "首次使用時，系統會引導匯入 liu.cin 字表",
                    "也可從設定程式 →「輸入」→「匯入字表⋯」手動匯入",
                    "字表在裝置上編譯為 .bin，不上傳、不外流",
                    "支援 .cin（主表）和 .txt（擴充表）",
                ])

                guide("基本打字", icon: "character.cursor.ibeam", steps: [
                    "輸入嘸蝦米碼，按空白鍵送字",
                    "候選字多於一個時，按 1–9 數字鍵選字",
                    "按 v / r / s / f 快速選第 2–5 候選字",
                    "按 * (Shift+8) 當萬用碼，不確定的碼用 * 代替",
                    "按 Enter 直接送出原始碼文字",
                    "按 / 空閒時直接送出（適合 slash command）",
                    "Tab / 方向鍵翻頁選字",
                ])

                guide("同音字查詢", icon: "character.phonetic", steps: [
                    "打 ,,TO + Space 進入同音字模式",
                    "進入後每次送字都會列出該字的同音字",
                    "用數字鍵選擇想送的同音字",
                    "在「輸入」頁開啟「同音字選後自動退出」後，選字會自動退出同音字模式",
                    "再打 ,,TO + Space 退出同音字模式",
                ])

                guide("注音反查與拼音查碼", icon: "textformat.abc", steps: [
                    "打 ,,ZH + Space → 切換注音反查（打注音看嘸蝦米碼）",
                    "再打 ,,ZH + Space 切回嘸蝦米",
                    "打 ,,PYS + Space → 拼音查碼（簡體）",
                    "打 ,,PYT + Space → 拼音查碼（繁體）",
                    "拼音模式：輸入拼音字母，按 1–5 選聲調（Space = 一聲）",
                ])

                guide("中英文切換", icon: "globe", steps: [
                    "單擊 Shift → 切換中／英文",
                    "按住 Shift → 暫時英文，放開回中文",
                    "Shift + Space → 全形空白",
                    ",, + Space → 全形空白（另一種方式）",
                ])

                #if !MINIMAL
                guide("聯想輸入", icon: "text.magnifyingglass", steps: [
                    "在「輸入」頁開啟聯想輸入",
                    "送字後自動顯示建議的下一個字／詞",
                    "按數字鍵選擇建議，或直接打碼忽略",
                    "三層來源：詞級語料（萌典/維基/新聞）→ 詞庫 → 字級（bigram/trigram）",
                    "在「聯想與詞庫」頁可拖拉調整層序（含 Emoji 聯想）與啟用詞庫",
                    "晶晶體為獨立來源；Emoji 聯想可移到最後或點卡片關閉",
                    "聯想策略設為「詞庫優先」時，同碼字排序會偏向你正在打的領域",
                ])
                #endif

                guide("擴充表", icon: "doc.text", steps: [
                    "擴充表放在 ~/Library/Application Support/Yabomish/tables/",
                    "格式：編碼<Tab>內容，一行一筆（# 開頭為註解）",
                    "修改後打 ,,RL + Space 即時重載",
                ])

                guide("固定同碼字排序", icon: "pin.fill", steps: [
                    "打 ,,PIN + Space 進入固定排序模式",
                    "輸入碼（如 hj），候選字列表出現",
                    "按數字鍵依序選擇要固定的字（如先選「手」再選「乎」）",
                    "按 Space 確認，該碼的候選順序即固定",
                    "打 ,,UNPINx + Space 解除（x 為碼，如 ,,UNPINhj）",
                    "也可在設定程式 →「輸入」→「固定同碼字排序」中操作",
                ])

                SectionDivider()

                // ── 快捷鍵速查 ──

                Label("快捷鍵速查", systemImage: "command").font(Typo.h1)

                section("基本操作", icon: "keyboard", items: [
                    ("空白鍵", "送字"),
                    ("1–9, 0", "選字"),
                    ("* (星號)", "萬用碼"),
                    ("v / r / s / f", "補碼（第 2–5 候選字）"),
                    ("' ; /", "直送（不攔截，方便寫程式）"),
                    ("Tab / ← →", "翻頁選字"),
                ])

                section("切換", icon: "arrow.left.arrow.right", items: [
                    ("Shift 單擊", "中／英文切換"),
                    ("Shift 按住", "暫時英文模式"),
                    ("Shift + Space", "全形空白"),
                ])

                section("命令模式（,, 開頭）", icon: "command", items: [
                    (",,T", "繁體中文（預設）"),
                    (",,S", "簡體中文"),
                    (",,J", "日文假名"),
                    (",,SP", "速打（僅最短碼）"),
                    (",,SL", "慢打（僅最長碼）"),
                    (",,TS", "繁→簡轉換"),
                    (",,ST", "簡→繁轉換"),
                    (",,ZH", "注音查碼"),
                    (",,PYT", "拼音查碼（繁體）"),
                    (",,PYS", "拼音查碼（簡體）"),
                    (",,TO", "同音字查詢模式"),
                    (",,RS", "重置字頻統計"),
                    (",,RL", "重載字表＋擴充表"),
                    (",,PIN", "固定同碼字排序"),
                    (",,UNPINx", "解除碼 x 的固定排序"),
                    (",,C", "顯示當前模式"),
                    (",,H", "命令說明"),
                    (",,LH", "查字歷史（最近 20 筆）"),
                    (",,RH", "清除查字歷史"),
                    (",,V", "貼上剪貼簿純文字"),
                    (",,VT／,,VS", "剪貼簿轉繁／轉簡後貼上"),
                ])

                #if !MINIMAL
                section("聯想與詞庫", icon: "text.magnifyingglass", items: [
                    (",,SG", "聯想輸入開／關"),
                    (",,XS／,,XI", "儲存／顯示語境設定"),
                    (",,X碼", "切換到指定語境（如 ,,Xit）"),
                    ("聯想層順序", "拖拉卡片調整「詞級語料」「詞庫」「字級聯想」的優先順序"),
                    ("詞級語料", "選擇萌典、維基或新聞作為詞組建議來源"),
                    ("一般詞庫", "點擊啟用／停用。拖拉調整建議優先順序"),
                    ("專業詞典", "點擊啟用所需領域。拖拉調整建議優先順序"),
                ])
                #endif

                section("擴充表", icon: "doc.text", items: [
                    ("路徑", "~/Library/Application Support/Yabomish/tables/*.txt"),
                    ("格式", "編碼<Tab>內容，一行一筆"),
                    ("重載", "修改後打 ,,RL 即時生效"),
                ])

                section("資料路徑", icon: "folder", items: [
                    ("liu.cin", "嘸蝦米字表"),
                    ("freq.db", "字頻學習資料"),
                    ("tables/", "擴充表資料夾"),
                    ("debug.log", "除錯記錄（開啟時）"),
                ])

                HStack {
                    Spacer()
                    Text("所有資料存放於 ~/Library/Application Support/\(dataDirName)/")
                        .font(Typo.caption).foregroundStyle(.tertiary)
                    Spacer()
                }

        }
        .onAppear { loadHelp() }
        } // 外層 VStack（搜尋＋內容）
    }

    private func loadHelp() {
        guard let url = Bundle.main.url(forResource: "help", withExtension: "md") else { return }
        helpText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - Guide (numbered steps)

    @ViewBuilder
    private func guide(_ title: String, icon: String, steps: [String]) -> some View {
        let q = helpQuery.trimmingCharacters(in: .whitespaces)
        let matched = q.isEmpty || title.localizedCaseInsensitiveContains(q)
            || steps.contains { $0.localizedCaseInsensitiveContains(q) }
        if matched {
            // 搜尋命中時自動展開；平時預設展開（前兩個由呼叫端順序決定視覺，全部可折疊）
            DisclosureGroup(isExpanded: guideExpanded(title)) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1).")
                                .font(Typo.bodyMono)
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .trailing)
                            Text(step).font(Typo.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            } label: {
                Label(title, systemImage: icon).font(Typo.h2)
            }
        }
    }

    /// guide 展開狀態：搜尋時命中項強制展開；平時預設展開，手工收起記憶在 expandedGuides
    private func guideExpanded(_ title: String) -> Binding<Bool> {
        let q = helpQuery.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { return .constant(true) }
        return Binding(
            get: { !collapsedGuides.contains(title) },
            set: { if $0 { collapsedGuides.remove(title) } else { collapsedGuides.insert(title) } }
        )
    }

    // MARK: - Section (key-value table)

    @ViewBuilder
    private func section(_ title: String, icon: String, items: [(String, String)]) -> some View {
        let hits: [(String, String)] = helpHits(items.map { ($0.0 + " " + $0.1, $0) })
        if !hits.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon).font(Typo.h2)
                ForEach(hits.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 0) {
                        Text(hits[i].0)
                            .font(Typo.bodyMono)
                            .frame(width: 180, alignment: .leading)
                        Text(hits[i].1)
                            .font(Typo.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

}
