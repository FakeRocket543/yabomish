import SwiftUI
import AppKit

private struct ToggleOption: Identifiable {
    let id: String
    let label: String
    let icon: String
    let desc: String
}

private let toastOptions: [ToggleOption] = [
    .init(id: "showActivateToast", label: "切入提示", icon: "bubble.middle.top", desc: "切換時顯示模式"),
    .init(id: "highContrast",      label: "高對比",   icon: "bold",             desc: "候選字加粗+陰影"),
    .init(id: "debugMode",         label: "Debug",   icon: "ladybug",           desc: "記錄操作日誌"),
]

private let iconOptions: [ToggleOption] = [
    .init(id: "left",  label: "← 向左", icon: "arrow.left",  desc: "蝦頭朝左"),
    .init(id: "right", label: "→ 向右", icon: "arrow.right", desc: "蝦頭朝右"),
]

struct AppearanceTab: View {
    @Bindable var store: PrefsStore

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                Label("字型大小", systemImage: "textformat.size").font(Typo.h2)
                VStack(spacing: 10) {
                    HStack {
                        Text("游標模式").font(Typo.body).frame(width: 80, alignment: .leading)
                        Slider(value: $store.fontSize, in: 10...30, step: 1)
                        Text("\(Int(store.fontSize)) pt").font(Typo.bodyMono).frame(width: 40, alignment: .trailing)
                    }
                    HStack {
                        Text("固定模式").font(Typo.body).frame(width: 80, alignment: .leading)
                        Slider(value: $store.fixedFontSize, in: 10...30, step: 1)
                        Text("\(Int(store.fixedFontSize)) pt").font(Typo.bodyMono).frame(width: 40, alignment: .trailing)
                    }
                    HStack {
                        Text("模式提示").font(Typo.body).frame(width: 80, alignment: .leading)
                        Slider(value: $store.toastFontSize, in: 20...72, step: 4)
                        Text("\(Int(store.toastFontSize)) pt").font(Typo.bodyMono).frame(width: 40, alignment: .trailing)
                    }
                    HStack {
                        Text("透明度").font(Typo.body).frame(width: 80, alignment: .leading)
                        Slider(value: $store.fixedAlpha, in: 0.3...1.0)
                        Text("\(Int(store.fixedAlpha * 100))%").font(Typo.bodyMono).frame(width: 40, alignment: .trailing)
                    }
                }

                // 預覽：游標模式（垂直）+ 固定模式（水平）
                HStack(alignment: .top, spacing: 24) {
                    // 游標模式 demo
                    VStack(alignment: .leading, spacing: 2) {
                        Text("游標模式").font(Typo.caption).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("1蝦").font(.system(size: store.fontSize))
                            Text("2米").font(.system(size: store.fontSize)).foregroundStyle(.secondary)
                            Text("3蟹").font(.system(size: store.fontSize)).foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
                    }

                    // 固定模式 demo
                    VStack(alignment: .leading, spacing: 2) {
                        Text("固定模式").font(Typo.caption).foregroundStyle(.secondary)
                        ZStack {
                            Canvas { ctx, size in
                                let s: CGFloat = 8
                                for row in 0..<Int(size.height / s) + 1 {
                                    for col in 0..<Int(size.width / s) + 1 {
                                        if (row + col) % 2 == 0 {
                                            ctx.fill(Path(CGRect(x: CGFloat(col) * s, y: CGFloat(row) * s, width: s, height: s)),
                                                     with: .color(.primary.opacity(0.08)))
                                        }
                                    }
                                }
                            }
                            .cornerRadius(8)

                            HStack(spacing: 12) {
                                Text("1蝦").font(.system(size: store.fixedFontSize))
                                Text("2米").font(.system(size: store.fixedFontSize)).foregroundStyle(.secondary)
                                Text("3蟹").font(.system(size: store.fixedFontSize)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .windowBackgroundColor).opacity(store.fixedAlpha))
                            )
                        }
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
                    }
                }
                .frame(maxWidth: .infinity)

                SectionDivider()
                Label("功能", systemImage: "switch.2").font(Typo.h2)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(toastOptions) { opt in
                        toggleCard(opt)
                    }
                }

                SectionDivider()
                Label("蝦頭方向", systemImage: "shippingbox").font(Typo.h2)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(iconOptions) { opt in
                        iconCard(opt)
                    }
                }

                if store.debugMode {
                    Button {
                        let url = URL(fileURLWithPath: NSHomeDirectory())
                            .appendingPathComponent("Library/YabomishIM/debug.log")
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("打開 debug.log⋯", systemImage: "doc.text.magnifyingglass")
                    }
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func toggleCard(_ opt: ToggleOption) -> some View {
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
    private func iconCard(_ opt: ToggleOption) -> some View {
        let selected = store.iconDirection == opt.id
        Button { store.iconDirection = opt.id } label: {
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

    private func binding(for key: String) -> Binding<Bool> {
        switch key {
        case "showActivateToast": return $store.showActivateToast
        case "highContrast":      return $store.highContrast
        case "debugMode":         return $store.debugMode
        default:                  return .constant(false)
        }
    }
}
