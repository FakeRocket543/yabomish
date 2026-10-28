import SwiftUI

/// 模式提示（中央 HUD）：切入提示開關＋字體／大小／透明度／顏色／描邊。
struct ToastTab: View {
    @Bindable var store: PrefsStore

    var body: some View {
        SettingsPage {
            SettingsSection(title: "切入提示",
                            footnote: "切換中／英模式或切入輸入法時，螢幕中央短暫顯示大字提示。") {
                ToggleRow(label: "顯示模式提示", icon: "bubble.middle.top",
                          desc: "切換時中央顯示「中／A」",
                          on: $store.showActivateToast)
            }

            SettingsSection(title: "字體") {
                VStack(spacing: 10) {
                    HStack {
                        Text("字型").font(Typo.body).frame(width: 80, alignment: .leading)
                        Picker("", selection: $store.toastFontStyle) {
                            Text("系統").tag("system")
                            Text("圓體").tag("rounded")
                            Text("明體").tag("serif")
                            Text("黑體").tag("heiti")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    sliderRow(label: "字級", value: $store.toastFontSize, in: 20...72, step: 2, format: { "\(Int($0)) pt" })
                    sliderRow(label: "透明度", value: $store.toastOpacity, in: 0.3...1.0, step: 0.05, format: { "\(Int($0 * 100))%" })
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }

            SettingsSection(title: "顏色",
                            footnote: "描邊如字幕外框：填色之上再描邊，亮背景下提示仍清晰。") {
                VStack(spacing: 10) {
                    HStack {
                        Text("字色").font(Typo.body).frame(width: 80, alignment: .leading)
                        ColorPicker("", selection: $store.toastTextColor.asColor(), supportsOpacity: false)
                            .labelsHidden()
                        Spacer()
                    }
                    HStack {
                        Text("描邊").font(Typo.body).frame(width: 80, alignment: .leading)
                        Toggle("", isOn: $store.toastStroke)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        if store.toastStroke {
                            ColorPicker("", selection: $store.toastStrokeColor.asColor(), supportsOpacity: false)
                                .labelsHidden()
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
    }

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
