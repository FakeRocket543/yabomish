import SwiftUI

/// 模式提示（中央 HUD）：切入提示開關＋字級／透明度。
/// 字體／字色／描邊已移到「候選窗」頁——與候選字共用同一組偏好。
struct ToastTab: View {
    @Bindable var store: PrefsStore

    var body: some View {
        SettingsPage {
            SettingsSection(title: "切入提示",
                            footnote: "切換中／英模式或切入輸入法時，螢幕中央短暫顯示大字提示。") {
                ToggleRow(label: "顯示模式提示", icon: "bell.badge",
                          desc: "切換時中央顯示「中／A」",
                          on: $store.showActivateToast)
            }

            SettingsSection(title: "顯示",
                            footnote: "字體、字色與描邊在「候選窗」頁設定，與候選字共用。") {
                VStack(spacing: 10) {
                    sliderRow(label: "字級", value: $store.toastFontSize, in: 20...72, step: 2, format: { "\(Int($0)) pt" })
                    sliderRow(label: "透明度", value: $store.toastOpacity, in: 0.3...1.0, step: 0.05, format: { "\(Int($0 * 100))%" })
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
