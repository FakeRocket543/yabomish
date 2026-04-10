import SwiftUI

struct InputTab: View {
    @Bindable var store: PrefsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("選字窗") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("位置", selection: $store.panelPosition) {
                            Text("游標跟隨").tag("cursor")
                            Text("固定位置").tag("fixed")
                        }
                        Picker("對齊", selection: $store.fixedAlignment) {
                            Text("靠左").tag("left")
                            Text("置中").tag("center")
                            Text("靠右").tag("right")
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("輸入") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("滿碼自動送字", isOn: $store.autoCommit)
                        Toggle("拆碼提示（送字後顯示嘸蝦米碼）", isOn: $store.showCodeHint)
                        Toggle("注音反查（'; 切換）", isOn: $store.zhuyinReverseLookup)
                        Toggle("同音多讀", isOn: $store.homophoneMultiReading)
                        Toggle("模糊匹配", isOn: $store.fuzzyMatch)
                    }
                    .padding(.vertical, 4)
                }

                Spacer()
            }
            .padding(20)
        }
    }
}
