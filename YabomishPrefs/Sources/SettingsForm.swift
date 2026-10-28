import SwiftUI

/// 頁面容器：置中限寬（系統設定式窄欄），全 tab 共用。
/// 取代各 tab 原本自寫的 ScrollView + VStack + .padding(20)。
struct SettingsPage<Content: View>: View {
    var maxWidth: CGFloat = 720
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Typo.sectionSpacing, content: content)
                .padding(20)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

/// 系統設定風格群組列容器：圓角底色 + 細邊框，內含多列（列間用 InsetDivider）。
/// 對應 macOS 系統設定的 grouped form section。
struct SettingsGroupBox<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0, content: content)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Typo.strokeOff.opacity(0.6), lineWidth: 0.5))
    }
}

/// 群組列內的列間分隔線（對齊文字左緣，不穿越圖示）。
struct InsetDivider: View {
    var body: some View {
        Divider().padding(.leading, 44)
    }
}

/// 單列開關：圖示 + 標題 + 說明 + 右側 Toggle（系統設定標準列）。
struct ToggleRow: View {
    let label: String
    let icon: String
    let desc: String
    @Binding var on: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Typo.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(Typo.body)
                Text(desc).font(Typo.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $on)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityHint(desc)
        .accessibilityValue(on ? "已啟用" : "已停用")
    }
}
