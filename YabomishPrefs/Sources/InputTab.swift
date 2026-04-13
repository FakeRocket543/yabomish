import SwiftUI

// MARK: - 媽祖廟五色（大甲鎮瀾宮龍柱配色）
// 暗色模式：fill opacity 0.20, stroke opacity 0.75
// 亮色模式：fill opacity 0.12, stroke opacity 0.55
private let mazuCyan   = Color(red: 143/255, green: 172/255, blue: 191/255) // #8FADBF 青灰 — 輸入功能
private let mazuGold   = Color(red: 242/255, green: 211/255, blue: 121/255) // #F2D479 金黃 — 選字窗
private let mazuOrange = Color(red: 242/255, green: 141/255, blue:  53/255) // #F28D35 橘   — 用詞習慣
private let mazuDeep   = Color(red: 242/255, green: 122/255, blue:  53/255) // #F27B35 深橘 — 聯想層
private let mazuRed    = Color(red: 242/255, green:  64/255, blue:  48/255) // #F24130 朱紅 — 詞級語料

private struct InputOption: Identifiable {
    let id: String
    let label: String
    let icon: String
    let desc: String
}

private let inputOptions: [InputOption] = [
    .init(id: "suggestEnabled",       label: "聯想輸入",  icon: "lightbulb",             desc: "送字後推薦候選"),
    .init(id: "autoCommit",           label: "自動送字",  icon: "arrow.right.circle",    desc: "滿碼自動送出"),
    .init(id: "showCodeHint",         label: "拆碼提示",  icon: "eye",                   desc: "送字後顯示碼"),
    .init(id: "zhuyinReverseLookup",  label: "注音反查",  icon: "character.phonetic",    desc: "'; 切換"),
    .init(id: "homophoneMultiReading",label: "同音多讀",  icon: "speaker.wave.2",        desc: "含罕見讀音"),
    .init(id: "fuzzyMatch",           label: "模糊匹配",  icon: "magnifyingglass",       desc: "鄰鍵容錯"),
    .init(id: "semanticSuggest",      label: "近似義建議", icon: "arrow.triangle.branch", desc: "Shift+數字替換近義詞"),
    .init(id: "punctuationPairing",   label: "標點配對",  icon: "quote.opening",         desc: "「→「」自動配對"),
]

private let panelOptions: [InputOption] = [
    .init(id: "cursor", label: "游標跟隨", icon: "cursorarrow.click", desc: "選字窗跟游標"),
    .init(id: "fixed",  label: "固定位置", icon: "rectangle.bottomhalf.filled", desc: "選字窗固定底部"),
]

private let regionOptions: [InputOption] = [
    .init(id: "tw", label: "臺灣用詞", icon: "漢", desc: "臺灣慣用詞優先"),
    .init(id: "cn", label: "中式用詞", icon: "汉", desc: "中式慣用詞優先"),
]

struct InputTab: View {
    @Bindable var store: PrefsStore

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("點擊卡片啟用／停用功能。")
                    .font(.callout).foregroundStyle(.secondary)

                Label("用詞習慣", systemImage: "map").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(regionOptions) { opt in
                        regionCard(opt)
                    }
                }

                Label("選字窗", systemImage: "keyboard").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(panelOptions) { opt in
                        panelCard(opt)
                    }
                }

                Label("輸入功能", systemImage: "character.cursor.ibeam").font(.headline)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(inputOptions) { opt in
                        toggleCard(opt)
                    }
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func toggleCard(_ opt: InputOption) -> some View {
        let on = binding(for: opt.id).wrappedValue
        Button { binding(for: opt.id).wrappedValue.toggle() } label: {
            VStack(spacing: 5) {
                Image(systemName: opt.icon)
                    .font(.system(size: 26))
                    .foregroundStyle(on ? mazuCyan : .secondary)
                Text(opt.label)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(opt.desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 100, height: 100)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(on ? mazuCyan.opacity(0.18) : .primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(on ? mazuCyan.opacity(0.7) : .primary.opacity(0.15),
                        lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func panelCard(_ opt: InputOption) -> some View {
        let selected = store.panelPosition == opt.id
        Button { store.panelPosition = opt.id } label: {
            VStack(spacing: 5) {
                Image(systemName: opt.icon)
                    .font(.system(size: 26))
                    .foregroundStyle(selected ? mazuGold : .secondary)
                Text(opt.label)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(opt.desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? mazuGold.opacity(0.18) : .primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? mazuGold.opacity(0.7) : .primary.opacity(0.15),
                        lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func regionCard(_ opt: InputOption) -> some View {
        let selected = store.regionVariant == opt.id
        Button { store.regionVariant = opt.id } label: {
            VStack(spacing: 5) {
                Text(opt.icon)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(selected ? mazuOrange : .secondary)
                Text(opt.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                Text(opt.desc)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? .secondary : .tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? mazuOrange.opacity(0.18) : .primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? mazuOrange.opacity(0.7) : .primary.opacity(0.15),
                        lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    private func binding(for key: String) -> Binding<Bool> {
        switch key {
        case "suggestEnabled":        return $store.suggestEnabled
        case "autoCommit":            return $store.autoCommit
        case "showCodeHint":          return $store.showCodeHint
        case "zhuyinReverseLookup":   return $store.zhuyinReverseLookup
        case "homophoneMultiReading": return $store.homophoneMultiReading
        case "fuzzyMatch":            return $store.fuzzyMatch
        case "semanticSuggest":       return $store.semanticSuggest
        case "punctuationPairing":    return $store.punctuationPairing
        default:                      return .constant(false)
        }
    }
}
