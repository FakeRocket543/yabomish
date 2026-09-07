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

private let iconOptions: [ToggleOption] = [
    .init(id: "left",  label: "← 向左", icon: "arrow.left",  desc: "蝦頭朝左"),
    .init(id: "right", label: "→ 向右", icon: "arrow.right", desc: "蝦頭朝右"),
]

private let switchOptions: [ToggleOption] = [
    .init(id: "繁中",     label: "繁中",     icon: "character",     desc: "傳統模式名"),
    .init(id: "Yabomish", label: "Yabomish", icon: "keyboard",      desc: "英文品牌名"),
    .init(id: "🦐",       label: "🦐",       icon: "face.smiling",  desc: "蝦子 emoji"),
]

private let appearanceOptions: [ToggleOption] = [
    .init(id: "auto",  label: "自動", icon: "circle.lefthalf.filled", desc: "跟隨系統外觀"),
    .init(id: "light", label: "淺色", icon: "sun.max",                desc: "固定淺色模式"),
    .init(id: "dark",  label: "深色", icon: "moon",                   desc: "固定深色模式"),
]

struct AppearanceTab: View {
    @Bindable var store: PrefsStore

    /// 蝦頭方向套用中（osascript 授權在背景執行，避免視窗凍結感）
    @State private var iconApplying = false
    /// 蝦頭方向的非封鎖小提示列（取消授權／套用結果）
    @State private var iconNotice: IconNotice?
    /// 蝦頭方向真的失敗時的 alert 內文
    @State private var iconError: String?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

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
                Label("切換顯示", systemImage: "text.badge.star").font(Typo.h2)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(switchOptions) { opt in
                        switchDisplayCard(opt)
                    }
                }

                SectionDivider()
                HStack(spacing: 8) {
                    Label("蝦頭方向", systemImage: "shippingbox").font(Typo.h2)
                    if iconApplying {
                        ProgressView().controlSize(.small)
                        Text("套用中⋯").font(Typo.caption).foregroundStyle(.secondary)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(iconOptions) { opt in
                        iconCard(opt)
                    }
                }
                Text("套用時需管理者授權，圖示於輸入法重啟後更新；若未立即生效，切換一次輸入法即可。")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                if let notice = iconNotice {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: notice.warning ? "exclamationmark.triangle" : "checkmark.circle")
                            .font(Typo.caption)
                        Text(notice.text).font(Typo.caption)
                        Spacer()
                        Button {
                            iconNotice = nil
                        } label: {
                            Image(systemName: "xmark").font(Typo.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(notice.warning ? Typo.warning : Typo.success)
                }

                if store.debugMode {
                    Button {
                        let url = URL(fileURLWithPath: NSHomeDirectory())
                            .appendingPathComponent("Library/Application Support/Yabomish/debug.log")
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("打開 debug.log⋯", systemImage: "doc.text.magnifyingglass")
                    }
                }
            }
            .padding(20)
        }
        .alert("套用失敗", isPresented: Binding(
            get: { iconError != nil },
            set: { if !$0 { iconError = nil } }
        )) {
            Button("好") { iconError = nil }
        } message: {
            Text(iconError ?? "")
        }
    }

    /// 蝦頭方向的非封鎖提示列資料
    private struct IconNotice: Identifiable {
        let id = UUID()
        let text: String
        let warning: Bool
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
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
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

    /// 選蝦頭方向：存偏好 + 以管理者授權覆寫安裝目錄的 icon.tiff + 重啟輸入法。
    /// 授權／複製在背景執行緒跑（IconApply 同步阻塞）；取消或失敗時還原偏好，
    /// 卡片勾選維持原方向——UI 不得停留在未套用的狀態。
    private func selectIcon(_ opt: ToggleOption) {
        guard !iconApplying, store.iconDirection != opt.id else { return }
        let previous = store.iconDirection
        iconApplying = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = IconApply.apply(direction: opt.id)
            DispatchQueue.main.async {
                iconApplying = false
                switch result {
                case .success(let outcome):
                    store.iconDirection = opt.id
                    if outcome == .applied {
                        IconApply.restartInputMethod()
                        iconNotice = .init(text: "已套用「\(opt.label)」。選單圖示會在輸入法重啟後更新；若未立即生效，切換一次輸入法即可。",
                                           warning: false)
                    } else {
                        iconNotice = .init(text: "安裝目錄圖示已是這個方向，設定已同步（免授權）。", warning: false)
                    }
                case .failure(.userCancelled):
                    // 使用者取消授權：還原偏好並以非封鎖提示告知
                    store.iconDirection = previous
                    iconNotice = .init(text: "已取消授權，圖示維持原方向。", warning: true)
                case .failure(let err):
                    // 真的失敗（找不到輸入法／來源圖缺／cp 錯誤）：還原偏好並彈出錯誤
                    store.iconDirection = previous
                    iconError = err.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private func iconCard(_ opt: ToggleOption) -> some View {
        SelectableCardView(label: opt.label, desc: opt.desc,
                           selected: store.iconDirection == opt.id,
                           icon: opt.icon) { selectIcon(opt) }
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
}
