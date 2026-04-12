import SwiftUI

private struct InputOption: Identifiable {
    let id: String
    let label: String
    let icon: String
    let desc: String
}

private let inputOptions: [InputOption] = [
    .init(id: "autoCommit",           label: "自動送字",  icon: "arrow.right.circle",    desc: "滿碼自動送出"),
    .init(id: "showCodeHint",         label: "拆碼提示",  icon: "eye",                   desc: "送字後顯示碼"),
    .init(id: "zhuyinReverseLookup",  label: "注音反查",  icon: "character.phonetic",    desc: "'; 切換"),
    .init(id: "homophoneMultiReading",label: "同音多讀",  icon: "speaker.wave.2",        desc: "含罕見讀音"),
    .init(id: "fuzzyMatch",           label: "模糊匹配",  icon: "magnifyingglass",       desc: "鄰鍵容錯"),
    .init(id: "punctuationPairing",   label: "標點配對",  icon: "quote.opening",         desc: "「→「」自動配對"),
]

private let panelOptions: [InputOption] = [
    .init(id: "cursor", label: "游標跟隨", icon: "cursorarrow.click", desc: "選字窗跟游標"),
    .init(id: "fixed",  label: "固定位置", icon: "rectangle.bottomhalf.filled", desc: "選字窗固定底部"),
]

struct InputTab: View {
    @Bindable var store: PrefsStore

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("點擊卡片啟用／停用功能。")
                    .font(.callout).foregroundStyle(.secondary)

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
            VStack(spacing: 6) {
                Image(systemName: opt.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(on ? Color.accentColor : .secondary)
                Text(opt.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(opt.desc)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 88, height: 88)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(on ? Color.accentColor.opacity(0.12) : Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(on ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor),
                        lineWidth: on ? 1.5 : 0.5))
            .opacity(on ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func panelCard(_ opt: InputOption) -> some View {
        let selected = store.panelPosition == opt.id
        Button { store.panelPosition = opt.id } label: {
            VStack(spacing: 6) {
                Image(systemName: opt.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Color.green : .secondary)
                Text(opt.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(opt.desc)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.green.opacity(0.12) : Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Color.green.opacity(0.5) : Color(nsColor: .separatorColor),
                        lineWidth: selected ? 1.5 : 0.5))
            .opacity(selected ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
    }

    private func binding(for key: String) -> Binding<Bool> {
        switch key {
        case "autoCommit":            return $store.autoCommit
        case "showCodeHint":          return $store.showCodeHint
        case "zhuyinReverseLookup":   return $store.zhuyinReverseLookup
        case "homophoneMultiReading": return $store.homophoneMultiReading
        case "fuzzyMatch":            return $store.fuzzyMatch
        case "punctuationPairing":    return $store.punctuationPairing
        default:                      return .constant(false)
        }
    }
}
