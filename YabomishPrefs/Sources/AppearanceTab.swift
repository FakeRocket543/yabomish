import SwiftUI
import AppKit

struct AppearanceTab: View {
    @Bindable var store: PrefsStore

    var body: some View {
        Form {
            HStack {
                Stepper("候選字大小：\(Int(store.fontSize)) pt", value: $store.fontSize, in: 10...30, step: 1)
                Text("蝦").font(.system(size: store.fontSize))
            }
            Stepper("固定模式大小：\(Int(store.fixedFontSize)) pt", value: $store.fixedFontSize, in: 10...30, step: 1)
            HStack {
                Text("透明度：")
                Slider(value: $store.fixedAlpha, in: 0.3...1.0)
                Text("\(Int(store.fixedAlpha * 100))%").monospacedDigit()
            }
            Stepper("模式提示大小：\(Int(store.toastFontSize)) pt", value: $store.toastFontSize, in: 20...72, step: 4)
            Toggle("切入時顯示模式提示", isOn: $store.showActivateToast)
            Picker("蝦頭方向", selection: $store.iconDirection) {
                Text("← 向左").tag("left")
                Text("→ 向右").tag("right")
            }
            Toggle("Debug 模式", isOn: $store.debugMode)
            Button("打開 debug.log...") {
                let url = URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("Library/YabomishIM/debug.log")
                NSWorkspace.shared.open(url)
            }
        }
        .padding()
    }
}
