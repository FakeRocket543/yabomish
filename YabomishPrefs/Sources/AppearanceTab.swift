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
    .init(id: "debugMode",         label: "除錯記錄",   icon: "ladybug",           desc: "記錄操作日誌"),
]


private let switchOptions: [ToggleOption] = [
    .init(id: "Yabo",     label: "Yabo",     icon: "textformat.abc", desc: "短名（推薦）"),
    .init(id: "Yabomish", label: "Yabomish", icon: "keyboard",      desc: "英文品牌名"),
]

private let appearanceOptions: [ToggleOption] = [
    .init(id: "auto",  label: "自動", icon: "circle.lefthalf.filled", desc: "跟隨系統外觀"),
    .init(id: "light", label: "淺色", icon: "sun.max",                desc: "固定淺色模式"),
    .init(id: "dark",  label: "深色", icon: "moon",                   desc: "固定深色模式"),
]

struct AppearanceTab: View {
    @Bindable var store: PrefsStore

    private let columns = [GridItem(.adaptive(minimum: 128), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Typo.sectionSpacing) {

                Label("介面外觀", systemImage: "circle.lefthalf.filled").font(Typo.h2)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(appearanceOptions) { opt in
                        appearanceModeCard(opt)
                    }
                }
                Text("套用對象：候選字窗、固定模式列與切換提示。設為「自動」時跟隨系統深淺色。")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)

                SectionDivider()
                Label("字型", systemImage: "textformat.size").font(Typo.h2)
                GroupBox {
                    VStack(spacing: 10) {
                        fontRow(label: "游標模式", value: $store.fontSize, in: 10...30, step: 1, format: { "\(Int($0)) pt" })
                        fontRow(label: "固定模式", value: $store.fixedFontSize, in: 10...30, step: 1, format: { "\(Int($0)) pt" })
                        fontRow(label: "模式提示", value: $store.toastFontSize, in: 20...72, step: 2, format: { "\(Int($0)) pt" })
                    }
                }

                SectionDivider()
                Label("固定窗背景", systemImage: "rectangle.transparent").font(Typo.h2)
                GroupBox {
                    VStack(spacing: 10) {
                        fontRow(label: "透明度", value: $store.fixedAlpha, in: 0.3...1.0, step: 0.05, format: { "\(Int($0 * 100))%" })
                        HStack {
                            Text("對齊").font(Typo.body)
                            Spacer()
                            Picker("", selection: $store.fixedAlignment) {
                                Text("左").tag("left")
                                Text("中").tag("center")
                                Text("右").tag("right")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                        }
                        HStack {
                            Text("垂直偏移").font(Typo.body)
                            Spacer()
                            Stepper("\(Int(store.fixedYOffset)) pt", value: $store.fixedYOffset, in: 0...64, step: 2)
                        }
                    }
                }

                // 預覽：游標模式（垂直/水平）+ 固定模式（水平）
                HStack(alignment: .top, spacing: 24) {
                    // 游標模式 demo
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("游標模式").font(Typo.caption).foregroundStyle(.secondary)
                            Toggle("橫向", isOn: $store.cursorHorizontal)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .font(Typo.caption)
                        }
                        if store.cursorHorizontal {
                            HStack(spacing: 8) {
                                Text("1蝦").font(.system(size: store.fontSize))
                                Text("2米").font(.system(size: store.fontSize)).foregroundStyle(.secondary)
                                Text("3蟹").font(.system(size: store.fontSize)).foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
                        } else {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("1蝦").font(.system(size: store.fontSize))
                                Text("2米").font(.system(size: store.fontSize)).foregroundStyle(.secondary)
                                Text("3蟹").font(.system(size: store.fontSize)).foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
                        }
                    }

                    // 固定模式 demo
                    VStack(alignment: .leading, spacing: 2) {
                        Text("固定模式").font(Typo.caption).foregroundStyle(.secondary)
                        ZStack {
                            CheckerPreview()

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
                Label("切換顯示", systemImage: "text.badge.star").font(Typo.h2)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(switchOptions) { opt in
                        switchDisplayCard(opt)
                    }
                }

                Button {
                    let url = URL(fileURLWithPath: NSHomeDirectory())
                        .appendingPathComponent("Library/Application Support/Yabomish/debug.log")
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("打開 debug.log⋯", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(!store.debugMode)
                .help(store.debugMode ? "" : "先開啟上方的除錯記錄卡片")
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func toggleCard(_ opt: ToggleOption) -> some View {
        let on = binding(for: opt.id).wrappedValue
        Button { binding(for: opt.id).wrappedValue.toggle() } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 5) {
                    Image(systemName: opt.icon)
                        .font(Typo.cardIcon)
                        .foregroundStyle(on ? Typo.accent : .secondary)
                    Text(opt.label)
                        .font(Typo.cardTitle)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(opt.desc)
                        .font(Typo.cardDesc)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: Typo.cardMinHeight)
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Typo.accent)
                        .padding(6)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(on ? Typo.accent.opacity(0.18) : Typo.cardOff))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(on ? Typo.accent.opacity(0.7) : Typo.strokeOff,
                        lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(opt.label)
        .accessibilityValue(on ? "已啟用" : "已停用")
    }


    @ViewBuilder
    private func appearanceModeCard(_ opt: ToggleOption) -> some View {
        SelectableCardView(label: opt.label, desc: opt.desc,
                           selected: store.appearanceMode == opt.id,
                           icon: opt.icon) { store.appearanceMode = opt.id }
    }

    @ViewBuilder
    private func switchDisplayCard(_ opt: ToggleOption) -> some View {
        SelectableCardView(label: opt.label, desc: opt.desc,
                           selected: store.switchDisplay == opt.id,
                           icon: opt.icon) { store.switchDisplay = opt.id }
    }

    private func binding(for key: String) -> Binding<Bool> {
        switch key {
        case "showActivateToast": return $store.showActivateToast
        case "highContrast":      return $store.highContrast
        case "debugMode":         return $store.debugMode
        default:                  return .constant(false)
        }
    }

    /// 字級／透明度列：Slider＋Stepper 共用同一 binding（鍵盤可操作），右側值 mono 顯示
    @ViewBuilder
    private func fontRow(label: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, format: @escaping (Double) -> String) -> some View {
        HStack {
            Text(label).font(Typo.body).frame(width: 64, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
            Text(format(value.wrappedValue)).font(Typo.bodyMono)
                .frame(minWidth: 48, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(format(value.wrappedValue))
    }
}

/// 固定窗透明度預覽的棋盤底（獨立 struct：避免寫在 body 裡每幀重算）
private struct CheckerPreview: View {
    var body: some View {
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
    }
}
