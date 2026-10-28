import SwiftUI

/// 候選窗外觀：位置、字型大小、固定模式背景、預覽。
struct CandidateTab: View {
    @Bindable var store: PrefsStore

    var body: some View {
        SettingsPage {
            SettingsSection(title: "選字窗位置") {
                ChoiceRow(label: "游標跟隨", icon: "cursorarrow.click",
                          desc: "選字窗跟游標",
                          selected: store.panelPosition == "cursor") { store.panelPosition = "cursor" }
                InsetDivider()
                ChoiceRow(label: "固定位置", icon: "rectangle.bottomhalf.filled",
                          desc: "選字窗固定底部",
                          selected: store.panelPosition == "fixed") { store.panelPosition = "fixed" }
            }

            // 預覽 — 只顯示選中的模式
            VStack(alignment: .leading, spacing: 6) {
                Text("預覽").font(Typo.caption).foregroundStyle(.secondary)
                Group {
                    if store.panelPosition == "cursor" {
                        cursorPreview
                    } else {
                        fixedPreview
                    }
                }
                .frame(maxWidth: .infinity)
            }

            SettingsSection(title: "字型大小") {
                VStack(spacing: 10) {
                    sliderRow(label: "游標模式", value: $store.fontSize, in: 10...30, step: 1, format: { "\(Int($0)) pt" })
                    sliderRow(label: "固定模式", value: $store.fixedFontSize, in: 10...30, step: 1, format: { "\(Int($0)) pt" })
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }

            SettingsSection(title: "固定窗背景") {
                VStack(spacing: 10) {
                    sliderRow(label: "透明度", value: $store.fixedAlpha, in: 0.3...1.0, step: 0.05, format: { "\(Int($0 * 100))%" })
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

            SettingsSection(title: "顯示") {
                ToggleRow(label: "橫向候選", icon: "rectangle.grid.1x2",
                          desc: "游標模式下候選橫排（預設直排）",
                          on: $store.cursorHorizontal)
                InsetDivider()
                ToggleRow(label: "高對比", icon: "bold",
                          desc: "候選字加粗＋陰影",
                          on: $store.highContrast)
            }
        }
    }

    // MARK: - Previews

    private var cursorPreview: some View {
        Group {
            if store.cursorHorizontal {
                HStack(spacing: 8) {
                    Text("1蝦").font(.system(size: store.fontSize))
                    Text("2米").font(.system(size: store.fontSize)).foregroundStyle(.secondary)
                    Text("3蟹").font(.system(size: store.fontSize)).foregroundStyle(.secondary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Typo.accent.opacity(0.7), lineWidth: 1.5))
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("1蝦").font(.system(size: store.fontSize))
                    Text("2米").font(.system(size: store.fontSize)).foregroundStyle(.secondary)
                    Text("3蟹").font(.system(size: store.fontSize)).foregroundStyle(.secondary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Typo.accent.opacity(0.7), lineWidth: 1.5))
            }
        }
    }

    private var fixedPreview: some View {
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

    /// 字級／透明度列：Slider＋Stepper 共用同一 binding（鍵盤可操作），右側值 mono 顯示
    @ViewBuilder
    private func sliderRow(label: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, format: @escaping (Double) -> String) -> some View {
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
