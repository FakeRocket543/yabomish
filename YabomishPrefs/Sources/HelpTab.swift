import SwiftUI

struct HelpTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

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
                    "再打 ,,TO + Space 退出同音字模式",
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
                ])

                Divider()

                // ── 快捷鍵速查 ──

                Label("快捷鍵速查", systemImage: "command").font(Typo.h1)

                section("基本操作", icon: "keyboard", items: [
                    ("空白鍵", "送字"),
                    ("1–9, 0", "選字"),
                    ("* (星號)", "萬用碼"),
                    ("v / r / s / f", "補碼（第 2–5 候選字）"),
                    ("' (單引號)", "頓號「、」"),
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
                    ("專業詞典", "點擊啟用所需領域。拖拉調整建議優先順序"),
                ])

                section("擴充表", icon: "doc.text", items: [
                    ("路徑", "~/Library/YabomishIM/tables/*.txt"),
                    ("格式", "編碼<Tab>內容，一行一筆"),
                    ("重載", "修改後打 ,,RL 即時生效"),
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
                        .font(Typo.caption).foregroundStyle(.tertiary)
                    Spacer()
                }

                Divider()

                // ── 語料來源與授權 ──

                Label("語料來源與授權", systemImage: "doc.text").font(Typo.h1)

                creditSection("核心資料", items: [
                    ("注音對照表", "威注音 VanguardLexicon", "MIT"),
                    ("繁簡對照表", "OpenCC", "Apache 2.0"),
                    ("萌典字頻", "萌典（教育部辭典）", "CC0"),
                    ("Emoji", "Unicode CLDR", "Unicode License"),
                ])
                creditSection("語料統計", items: [
                    ("維基語料", "中文維基百科 zhwiki dump", "CC-BY-SA 3.0"),
                    ("新聞詞頻", "國家教育研究院 新聞語料庫", "政府開放資料"),
                ])
                creditSection("一般詞庫", items: [
                    ("成語", "教育部成語典", "政府開放資料"),
                    ("歇後語", "chinese-xinhua", "MIT"),
                    ("台灣俗諺", "教育部閩南語常用詞辭典", "政府開放資料"),
                    ("客語辭典（六腔）", "教育部臺灣客語辭典", "政府開放資料"),
                    ("台灣地名", "教育部本土語言地名", "CC-BY 3.0 TW"),
                    ("台語學科", "教育部台語學科術語", "CC-BY 3.0 TW"),
                    ("韓語漢字詞", "Kengdic", "MPL 2.0"),
                    ("兩岸用詞對照", "國家教育研究院 樂詞網", "政府開放資料"),
                ])
                creditSection("專業詞典", items: [
                    ("專業詞典 ×23", "國家教育研究院 樂詞網（NAER）", "政府開放資料"),
                    ("外國地名", "國家教育研究院 譯名", "政府開放資料"),
                ])

                Text("本程式碼以 MIT 授權釋出。各語料依其原始授權條款使用。")
                    .font(Typo.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    // MARK: - Guide (numbered steps)

    @ViewBuilder
    private func guide(_ title: String, icon: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(Typo.h2)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1).")
                        .font(Typo.bodyMono)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                    Text(step).font(Typo.body)
                }
            }
        }
    }

    // MARK: - Section (key-value table)

    @ViewBuilder
    private func section(_ title: String, icon: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(Typo.h2)
            ForEach(items, id: \.0) { key, desc in
                HStack(alignment: .top, spacing: 0) {
                    Text(key)
                        .font(Typo.bodyMono)
                        .frame(width: 160, alignment: .leading)
                    Text(desc)
                        .font(Typo.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Credit section (name / source / license)

    @ViewBuilder
    private func creditSection(_ title: String, items: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Typo.h3).foregroundStyle(.secondary)
            ForEach(items, id: \.0) { name, source, license in
                HStack(alignment: .top, spacing: 0) {
                    Text(name).font(Typo.bodyMono).frame(width: 140, alignment: .leading)
                    Text(source).font(Typo.body).frame(width: 220, alignment: .leading)
                    Text(license).font(Typo.cardDesc).foregroundStyle(.secondary)
                }
            }
        }
    }
}
