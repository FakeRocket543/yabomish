import SwiftUI

struct UsageTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

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
                    "剛送字後按 ' → 立即列出該字的同音字",
                    "空閒時按 ' → 進入同音字模式，之後每次送字都會列同音字",
                    "同音字模式下按 ' 再按 Space → 輸出頓號「、」",
                    "打 ,,TO + Space 也可切換同音字模式",
                ])

                guide("注音反查與拼音查碼", icon: "textformat.abc", steps: [
                    "同音字模式下按 '; → 切換注音反查（打注音看嘸蝦米碼）",
                    "再按 '; 切回嘸蝦米",
                    "打 ,,ZH + Space 也可切換注音反查",
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

                guide("命令模式（,, 開頭 + Space 確認）", icon: "command", steps: [
                    ",,T 繁中　,,S 簡中　,,J 日文假名",
                    ",,SP 速打（僅最短碼）　,,SL 慢打（僅最長碼）",
                    ",,TS 繁→簡轉換　,,ST 簡→繁轉換",
                    ",,ZH 注音查碼　,,TO 同音字模式",
                    ",,PYS 拼音查碼（簡）　,,PYT 拼音查碼（繁）",
                    ",,RS 重置字頻統計　,,RL 重載字表＋擴充表",
                    ",,C 顯示當前模式　,,H 命令說明",
                ])

                guide("聯想輸入", icon: "text.magnifyingglass", steps: [
                    "在「輸入」頁開啟聯想輸入",
                    "送字後自動顯示建議的下一個字／詞",
                    "按數字鍵選擇建議，或直接打碼忽略",
                    "三層來源：詞級語料（萌典/維基/新聞）→ 詞庫 → 字級（bigram/trigram）",
                    "在「聯想與詞庫」頁可拖拉調整三層順序與啟用詞庫",
                    "晶晶體、Emoji 聯想為獨立來源",
                    "聯想策略設為「詞庫優先」時，同碼字排序會偏向你正在打的領域",
                ])

                guide("擴充表", icon: "doc.text", steps: [
                    "擴充表放在 ~/Library/YabomishIM/tables/",
                    "格式：編碼<Tab>內容，一行一筆",
                    "修改後打 ,,RL + Space 即時重載",
                    "預設 emoji.txt（em 開頭五碼）",
                ])

                HStack {
                    Spacer()
                    Text("更多快捷鍵速查請參考「說明」頁")
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func guide(_ title: String, icon: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1).")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                    Text(step)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}
