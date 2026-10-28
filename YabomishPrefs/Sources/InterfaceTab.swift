import SwiftUI
import AppKit

/// 介面外觀：深淺色模式、輸入法選單顯示名稱、除錯記錄。
struct InterfaceTab: View {
    @Bindable var store: PrefsStore

    var body: some View {
        SettingsPage {
            SettingsSection(title: "介面外觀",
                            footnote: "套用對象：候選字窗、固定模式列與切換提示。設為「自動」時跟隨系統深淺色。") {
                SegmentedRow("模式", selection: $store.appearanceMode,
                             options: [("auto", "自動"), ("light", "淺色"), ("dark", "深色")])
            }

            SettingsSection(title: "視覺效果",
                            footnote: "「完整」啟用 Liquid Glass：HUD 中央提示呈玻璃質感、語境膠囊與搜尋欄帶折射效果（需 macOS 26 以上，舊系統自動回落）。「無」改為純色不透明、不含任何玻璃或材質效果。") {
                SegmentedRow("效果等級", selection: $store.visualEffects,
                             options: [("full", "完整"), ("none", "無")])
            }

            SettingsSection(title: "切換顯示",
                            footnote: "切換輸入法時，輸入法選單與切入提示顯示的名稱。") {
                SegmentedRow("名稱", selection: $store.switchDisplay,
                             options: [("Yabo", "Yabo"), ("Yabomish", "Yabomish")])
            }

            SettingsSection(title: "除錯",
                            footnote: "記錄輸入法操作日誌至 debug.log（安全輸入期間一律靜音）。") {
                ToggleRow(label: "除錯記錄", icon: "ladybug",
                          desc: "記錄操作日誌",
                          on: $store.debugMode)
                InsetDivider()
                HStack {
                    Text("記錄檔").font(Typo.body)
                    Spacer()
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
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
    }
}
