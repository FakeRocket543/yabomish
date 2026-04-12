import SwiftUI

struct HelpTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                section("基本操作", icon: "keyboard", items: [
                    ("空白鍵", "送字"),
                    ("1–9, 0", "選字"),
                    ("* (星號)", "萬用碼"),
                    ("v / r / s / f", "補碼（第 2–5 候選字）"),
                    ("' (單引號)", "同音字查詢"),
                    ("';", "注音反查模式"),
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
                    (",,C", "顯示當前模式"),
                    (",,H", "命令說明"),
                ])

                section("聯想與詞庫", icon: "text.magnifyingglass", items: [
                    ("聯想層順序", "拖拉卡片調整「詞級語料」「詞庫」「字級聯想」的優先順序"),
                    ("詞級語料", "選擇萌典、維基或新聞作為詞組建議來源"),
                    ("一般詞庫", "點擊啟用／停用。拖拉調整建議優先順序"),
                    ("專業詞典", "點擊啟用所需領域。排序越前面，建議越優先"),
                ])

                section("擴充表", icon: "doc.text", items: [
                    ("路徑", "~/Library/YabomishIM/tables/*.txt"),
                    ("格式", "編碼<Tab>內容，一行一筆"),
                    ("重載", "修改後打 ,,RL 即時生效"),
                    ("Emoji", "預設 emoji.txt（em 開頭五碼）"),
                ])

                section("資料路徑", icon: "folder", items: [
                    ("liu.cin", "嘸蝦米字表"),
                    ("freq.db", "字頻學習資料"),
                    ("tables/", "擴充表資料夾"),
                    ("debug.log", "Debug 日誌（開啟時）"),
                ])

                HStack {
                    Spacer()
                    Text("所有資料存放於 ~/Library/YabomishIM/")
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func section(_ title: String, icon: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            ForEach(items, id: \.0) { key, desc in
                HStack(alignment: .top, spacing: 0) {
                    Text(key)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(width: 160, alignment: .leading)
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
