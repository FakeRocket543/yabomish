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


struct AppearanceTab: View {
    @Bindable var store: PrefsStore

    var body: some View {
        SettingsPage {

                SettingsSection(title: "介面外觀",
                                footnote: "套用對象：候選字窗、固定模式列與切換提示。設為「自動」時跟隨系統深淺色。") {
                    SegmentedRow("模式", selection: $store.appearanceMode,
                                 options: [("auto", "自動"), ("light", "淺色"), ("dark", "深色")])
                }

                SettingsSection(title: "字型") {
                    VStack(spacing: 10) {
                        fontRow(label: "游標模式", value: $store.fontSize, in: 10...30, step: 1, format: { "\(Int($0)) pt" })
                        fontRow(label: "固定模式", value: $store.fixedFontSize, in: 10...30, step: 1, format: { "\(Int($0)) pt" })
                        fontRow(label: "模式提示", value: $store.toastFontSize, in: 20...72, step: 2, format: { "\(Int($0)) pt" })
                        fontRow(label: "提示透明度", value: $store.toastOpacity, in: 0.3...1.0, step: 0.05, format: { "\(Int($0 * 100))%" })
                        HStack {
                            Text("提示字體").font(Typo.body).frame(width: 80, alignment: .leading)
                            Picker("", selection: $store.toastFontStyle) {
                                Text("系統").tag("system")
                                Text("圓體").tag("rounded")
                                Text("明體").tag("serif")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                        HStack {
                            Text("提示字色").font(Typo.body).frame(width: 80, alignment: .leading)
                            ColorPicker("", selection: $store.toastTextColor.asColor(), supportsOpacity: false)
                                .labelsHidden()
                            Spacer()
                            Toggle("描邊", isOn: $store.toastStroke)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            if store.toastStroke {
                                ColorPicker("", selection: $store.toastStrokeColor.asColor(), supportsOpacity: false)
                                    .labelsHidden()
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }

                SettingsSection(title: "固定窗背景") {
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
                    .padding(.horizontal, 12).padding(.vertical, 8)
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

                SettingsSection(title: "功能") {
                    ForEach(Array(toastOptions.enumerated()), id: \.element.id) { i, opt in
                        if i > 0 { InsetDivider() }
                        ToggleRow(label: opt.label, icon: opt.icon, desc: opt.desc,
                                  on: binding(for: opt.id))
                    }
                }

                SettingsSection(title: "切換顯示",
                                footnote: "切換輸入法時，輸入法選單與切入提示顯示的名稱。") {
                    SegmentedRow("名稱", selection: $store.switchDisplay,
                                 options: [("Yabo", "Yabo"), ("Yabomish", "Yabomish")])
                }

                Button {
                    let url = URL(fileURLWithPath: NSHomeDirectory())
                        .appendingPathComponent("Library/Application Support/\(store.dataDirName)/debug.log")
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("打開 debug.log⋯", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(!store.debugMode)
                .help(store.debugMode ? "" : "先開啟上方的除錯記錄開關")
        }
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
            Text(label).font(Typo.body).frame(width: 80, alignment: .leading)
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
