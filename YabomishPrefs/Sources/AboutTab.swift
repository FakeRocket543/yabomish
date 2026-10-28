import SwiftUI

/// 關於：版本、回報、語料來源與授權、原始碼連結。
struct AboutTab: View {
    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        SettingsPage {
            SettingsGroupBox {
                HStack(spacing: 12) {
                    Image(systemName: "character.textbox")
                        .font(.system(size: 28))
                        .foregroundStyle(Typo.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Yabomish").font(Typo.h2)
                        Text(versionLine)
                            .font(Typo.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Spacer()
                    Link("回報問題",
                         destination: URL(string: "https://github.com/FakeRocket543/yabomish/issues/new")!)
                        .font(Typo.body)
                }
                .padding(.horizontal, 12).padding(.vertical, 12)
            }

            // ── 語料來源與授權 ──
            #if MINIMAL
            creditSection("核心資料", items: [
                ("注音對照表", "威注音 VanguardLexicon", "MIT"),
                ("繁簡對照表", "OpenCC", "Apache 2.0"),
                ("萌典字頻", "萌典（教育部辭典）", "CC0"),
            ])
            #else
            creditSection("核心資料", items: [
                ("注音對照表", "威注音 VanguardLexicon", "MIT"),
                ("繁簡對照表", "OpenCC", "Apache 2.0"),
                ("萌典字頻", "萌典（教育部辭典）", "CC0"),
                ("Emoji", "Unicode CLDR", "Unicode License"),
            ])
            creditSection("語料統計", items: [
                ("維基語料", "中文維基百科 zhwiki dump", "CC-BY-SA 3.0"),
                ("新聞詞頻", "國家教育研究院 新聞語料庫", "政府開放資料"),
                ("英文常用詞", "google-10000-english", "Public Domain"),
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
                ("專業詞典 ×28", "國家教育研究院 樂詞網（NAER）", "政府開放資料"),
                ("外國地名", "國家教育研究院 譯名", "政府開放資料"),
            ])
            #endif

            Text("本程式碼以 MIT 授權釋出。各語料依其原始授權條款使用。")
                .font(Typo.caption).foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Text("原始碼：").font(Typo.caption).foregroundStyle(.secondary)
                Link("github.com/FakeRocket543/yabomish",
                     destination: URL(string: "https://github.com/FakeRocket543/yabomish")!)
                    .font(Typo.caption)
            }
        }
    }

    // MARK: - Credit section (name / source / license)

    @ViewBuilder
    private func creditSection(_ title: String, items: [(String, String, String)]) -> some View {
        SettingsSection(title: title) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0 { InsetDivider() }
                HStack(spacing: 0) {
                    Text(item.0)
                        .font(Typo.bodyMono)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.1)
                        .font(Typo.body)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.2)
                        .font(Typo.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
    }
}
