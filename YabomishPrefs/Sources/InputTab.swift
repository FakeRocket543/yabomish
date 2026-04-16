import SwiftUI


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
                // CIN import — first thing users need
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("嘸蝦米字表（liu.cin）", systemImage: "doc.badge.arrow.up").font(Typo.h2)
                        Text("Yabomish 需要嘸蝦米的 .cin 字表檔才能運作。如果你有購買嘸蝦米輸入法，請從安裝目錄中找到 liu.cin，點擊下方按鈕匯入。字表僅在本機編譯使用，不會上傳。")
                            .font(Typo.body).foregroundStyle(.secondary)
                        HStack {
                            Button {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.init(filenameExtension: "cin")!, .plainText]
                                panel.message = "選擇嘸蝦米字表（.cin）或擴充表（.txt）"
                                guard panel.runModal() == .OK, let url = panel.url else { return }
                                let dest = NSHomeDirectory() + "/Library/YabomishIM/"
                                try? FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
                                let target = dest + url.lastPathComponent
                                try? FileManager.default.copyItem(atPath: url.path, toPath: target)
                                DistributedNotificationCenter.default().post(name: .init("com.yabomish.reloadTables"), object: nil)
                            } label: {
                                Label("匯入字表⋯", systemImage: "folder.badge.plus")
                            }
                            Spacer()
                        }
                    }
                    .padding(4)
                }

                Text("點擊卡片啟用／停用功能。")
                    .font(Typo.hint).foregroundStyle(.secondary)

                Label("用詞習慣", systemImage: "map").font(Typo.h2)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(regionOptions) { opt in
                        regionCard(opt)
                    }
                }

                SectionDivider()
                Label("選字窗", systemImage: "keyboard").font(Typo.h2)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(panelOptions) { opt in
                        panelCard(opt)
                    }
                }

                // 選字窗 demo — 只顯示選中的模式
                Group {
                    if store.panelPosition == "cursor" {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("1蝦").font(.system(size: 16))
                            Text("2米").font(.system(size: 16)).foregroundStyle(.secondary)
                            Text("3蟹").font(.system(size: 16)).foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Typo.gold.opacity(0.7), lineWidth: 1.5))
                    } else {
                        HStack(spacing: 10) {
                            Text("1蝦").font(.system(size: 16))
                            Text("2米").font(.system(size: 16)).foregroundStyle(.secondary)
                            Text("3蟹").font(.system(size: 16)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Typo.gold.opacity(0.7), lineWidth: 1.5))
                    }
                }
                .frame(maxWidth: .infinity)

                SectionDivider()
                Label("輸入功能", systemImage: "character.cursor.ibeam").font(Typo.h2)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(inputOptions) { opt in
                        toggleCard(opt)
                    }
                }

                // ── 固定排序 ──
                SectionDivider()
                Label("固定同碼字排序", systemImage: "pin.fill").font(Typo.h2)
                Text("指定某碼的候選字固定順序，不受學習排序影響。")
                    .font(Typo.hint).foregroundStyle(.secondary)
                PinnedOrderSection()

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
                    .font(Typo.cardIcon)
                    .foregroundStyle(on ? Typo.cyan : .secondary)
                Text(opt.label)
                    .font(Typo.cardTitle)
                    .lineLimit(1)
                Text(opt.desc)
                    .font(Typo.cardDesc)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 110, height: 100)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(on ? Typo.cyan.opacity(0.18) : Typo.cardOff))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(on ? Typo.cyan.opacity(0.7) : Typo.strokeOff,
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
                    .font(Typo.cardIcon)
                    .foregroundStyle(selected ? Typo.gold : .secondary)
                Text(opt.label)
                    .font(Typo.cardTitle)
                    .lineLimit(1)
                Text(opt.desc)
                    .font(Typo.cardDesc)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Typo.gold.opacity(0.18) : Typo.cardOff))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Typo.gold.opacity(0.7) : Typo.strokeOff,
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
                    .foregroundStyle(selected ? Typo.orange : .secondary)
                Text(opt.label)
                    .font(Typo.cardTitle)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                Text(opt.desc)
                    .font(Typo.cardDesc)
                    .foregroundStyle(selected ? .secondary : .tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Typo.orange.opacity(0.18) : Typo.cardOff))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Typo.orange.opacity(0.7) : Typo.strokeOff,
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
        case "punctuationPairing":    return $store.punctuationPairing
        default:                      return .constant(false)
        }
    }
}
