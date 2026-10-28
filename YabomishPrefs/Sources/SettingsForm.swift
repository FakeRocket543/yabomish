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

/// 系統設定式區塊：標題＋群組列盒＋可選註腳，間距貼近原生設定。
struct SettingsSection<Content: View>: View {
    var title: String? = nil
    var footnote: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { SettingsHeader(title) }
            SettingsGroupBox(content: content)
            if let footnote { SettingsFootnote(footnote) }
        }
    }
}

/// 系統設定式區塊標題：純文字粗體小標（原生設定區塊不帶圖示、無分隔線）。
struct SettingsHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .padding(.leading, 12)
    }
}

/// 群組下方的說明註腳（系統設定慣用的小字灰說明）。
struct SettingsFootnote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Typo.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
    }
}

/// 群組列內的單選列（系統設定式：選中列右側顯示勾選記號）。
/// 用於互斥選項——取代卡片網格，更接近原生設定。
struct ChoiceRow: View {
    let label: String
    var icon: String? = nil
    var desc: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(selected ? Typo.accent : .secondary)
                        .frame(width: 22)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(Typo.body)
                    if let desc {
                        Text(desc).font(Typo.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Typo.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(selected ? "已選擇" : "未選擇")
    }
}

/// 群組列內的 segmented 選擇列：短選項（2–4 個單詞）適用，最貼近原生設定。
struct SegmentedRow<Selection: Hashable>: View {
    let label: String
    @Binding var selection: Selection
    let options: [(Selection, String)]

    init(_ label: String, selection: Binding<Selection>,
         options: [(Selection, String)]) {
        self.label = label
        self._selection = selection
        self.options = options
    }

    var body: some View {
        HStack {
            Text(label).font(Typo.body)
            Spacer()
            Picker("", selection: $selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
