import SwiftUI

/// 切換設定：中英切換鍵 + 密碼／安全欄位放行。
/// 兩者都回答同一個問題——「什麼時候輸入法該讓位」。
struct SwitchTab: View {
    @Bindable var store: PrefsStore

    var body: some View {
        SettingsPage {
            SettingsSection(title: "中英切換鍵",
                            footnote: "切換中／英模式的按鍵。選 ⇪ 或「兩者」後 Caps Lock 成為專用切換鍵（大寫燈不亮、大寫改由 Shift＋字母）；注意 macOS 會丟棄過快的輕點（<100ms），需稍長一點按壓。選「全都不用」時英文改從輸入法選單點選。") {
                ChoiceRow(label: "Shift 快按", icon: "shift",
                          desc: "全系統慣例（預設）",
                          selected: store.englishToggleKey == "shift") { store.englishToggleKey = "shift" }
                InsetDivider()
                ChoiceRow(label: "⇪ Caps Lock", icon: "capslock",
                          desc: "改用 ⇪ 切換",
                          selected: store.englishToggleKey == "capslock") { store.englishToggleKey = "capslock" }
                InsetDivider()
                ChoiceRow(label: "兩者皆可", icon: "keyboard",
                          desc: "⇪ 與 Shift 快按都能切",
                          selected: store.englishToggleKey == "both") { store.englishToggleKey = "both" }
                InsetDivider()
                ChoiceRow(label: "全都不用", icon: "keyboard.badge.ellipsis",
                          desc: "只從輸入法選單切換",
                          selected: store.englishToggleKey == "none") { store.englishToggleKey = "none" }
            }

            SettingsSection(title: "密碼／安全欄位",
                            footnote: "macOS 安全輸入啟用時（密碼欄、Keychain 對話框等），預設輸入法暫停、按鍵原樣送達——避免組字緩衝、字頻學習、debug 記錄接觸密碼。某些 app 會卡住安全輸入不放，造成整個 app 無法輸入；此時可開啟上方選項強行使用。無論是否開啟，安全期間 debug 記錄與字頻學習一律靜音。") {
                ToggleRow(label: "密碼欄位照打", icon: "lock.open",
                          desc: "安全輸入時仍處理按鍵（預設關，慎用）",
                          on: $store.allowSecureInput)
            }
        }
    }
}
