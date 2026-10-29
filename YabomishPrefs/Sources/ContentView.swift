import SwiftUI

extension Notification.Name {
    /// View menu Cmd+數字 切換側邊欄頁面（main.swift 的 selectTab 發送，object 為 Int tag）
    static let selectPrefsTab = Notification.Name("com.yabomish.selectPrefsTab")
}

/// 側邊欄導覽項目（full/min 兩種 build 各一份）。
/// 搜尋欄底層：glass=true 且 macOS 26+ → Liquid Glass；否則純色底。
private struct SearchSurface: ViewModifier {
    let glass: Bool
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), glass {
            content.glassEffect(.regular, in: .rect(cornerRadius: 7))
        } else {
            content.background(RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor)))
        }
    }
}

private struct NavItem: Identifiable {
    let tag: Int
    let title: String
    let icon: String
    let color: Color
    var id: Int { tag }
}

#if !MINIMAL
private let navItems: [NavItem] = [
    .init(tag: 0,  title: "輸入",     icon: "keyboard",               color: .blue),
    .init(tag: 1,  title: "切換",     icon: "arrow.left.arrow.right", color: .teal),
    .init(tag: 2,  title: "英數",     icon: "textformat.abc",         color: .cyan),
    .init(tag: 3,  title: "聯想",     icon: "lightbulb",              color: .purple),
    .init(tag: 4,  title: "一般詞庫", icon: "books.vertical",         color: .indigo),
    .init(tag: 5,  title: "專業詞庫", icon: "graduationcap",              color: .brown),
    .init(tag: 6,  title: "快捷碼",   icon: "command",                   color: .yellow),
    .init(tag: 7,  title: "候選窗",   icon: "list.bullet.rectangle",  color: .orange),
    .init(tag: 8,  title: "模式提示", icon: "bell.badge",      color: .pink),
    .init(tag: 9,  title: "介面",     icon: "circle.lefthalf.filled",             color: .red),
    .init(tag: 10, title: "說明",     icon: "book",                   color: .green),
    .init(tag: 11, title: "關於",     icon: "info.circle",            color: .gray),
]
#else
private let navItems: [NavItem] = [
    .init(tag: 0, title: "輸入",     icon: "keyboard",               color: .blue),
    .init(tag: 1, title: "切換",     icon: "arrow.left.arrow.right", color: .teal),
    .init(tag: 2, title: "英數",     icon: "textformat.abc",         color: .cyan),
    .init(tag: 3, title: "快捷碼",   icon: "command",                   color: .yellow),
    .init(tag: 4, title: "候選窗",   icon: "list.bullet.rectangle",  color: .orange),
    .init(tag: 5, title: "模式提示", icon: "bell.badge",      color: .pink),
    .init(tag: 6, title: "介面",     icon: "circle.lefthalf.filled",             color: .red),
    .init(tag: 7, title: "說明",     icon: "book",                   color: .green),
    .init(tag: 8, title: "關於",     icon: "info.circle",            color: .gray),
]
#endif

/// 搜尋索引條目：細功能名稱 → 所屬頁（以頁面標題對應 NavItem，
/// 不用固定 tag —— full/min 兩種 build 的 tag 編號不同，靠標題解析才穩）。
/// 使用者打關鍵字 → 結果列顯示「設定名（頁名）」→ 點了跳頁。
private struct SettingHit: Identifiable {
    let title: String
    let page: String
    let keywords: String
    var id: String { "\(page):\(title)" }
}

private let settingIndex: [SettingHit] = [
    // 輸入
    .init(title: "匯入字表",       page: "輸入", keywords: "liu cin 字表 匯入 import"),
    .init(title: "自動送字",       page: "輸入", keywords: "滿碼 auto commit"),
    .init(title: "拆碼提示",       page: "輸入", keywords: "送字顯示碼 code hint"),
    .init(title: "同音多讀",       page: "輸入", keywords: "讀音 homophone"),
    .init(title: "同音字選後自動退出", page: "輸入", keywords: "同音字 auto exit"),
    .init(title: "鄰鍵容錯",       page: "輸入", keywords: "打錯 fuzzy"),
    .init(title: "標點配對",       page: "輸入", keywords: "括號 quote"),
    .init(title: "Shift＋數字鍵",  page: "輸入", keywords: "符號 數字 shift digit"),
    .init(title: "固定同碼字排序", page: "輸入", keywords: "pin 固定 排序"),
    .init(title: "查字歷史",       page: "輸入", keywords: "反查 歷史 lookup"),
    // 切換
    .init(title: "中英切換鍵",     page: "切換", keywords: "shift caps lock 切換 英文 capslock"),
    .init(title: "密碼欄位照打",   page: "切換", keywords: "密碼 安全欄位 secure password"),
    // 英數
    .init(title: "英文聯想輸入",   page: "英數", keywords: "英文 補全 autocomplete english"),
    .init(title: "自訂詞",         page: "英數", keywords: "自訂詞 user dict 單字"),
    // 聯想（min build 無此頁——page 對不到 NavItem 自動隱藏）
    .init(title: "聯想輸入",       page: "聯想", keywords: "聯想 suggest 推薦"),
    .init(title: "聯想預先反白",   page: "聯想", keywords: "反白 preselect"),
    .init(title: "語境切換",       page: "聯想", keywords: "語境 context"),
    .init(title: "聯想層順序",     page: "聯想", keywords: "層 順序 emoji 詞庫 字級"),
    .init(title: "詞級語料來源",   page: "聯想", keywords: "萌典 維基 新聞 corpus"),
    .init(title: "用詞習慣",       page: "聯想", keywords: "台灣 中式 地區 region"),
    // 詞庫（min 無）
    .init(title: "一般詞庫",       page: "一般詞庫", keywords: "成語 歇後語 台語 客語 詞庫 domain"),
    .init(title: "專業詞庫",       page: "專業詞庫", keywords: "醫學 法律 資訊 專業 樂詞網 domain"),
    // 快捷碼
    .init(title: "快捷碼",         page: "快捷碼", keywords: "快捷碼 shortcut"),
    // 候選窗
    .init(title: "選字窗位置",     page: "候選窗", keywords: "游標 固定 位置 panel"),
    .init(title: "候選字大小",     page: "候選窗", keywords: "字級 字型 font size"),
    .init(title: "固定窗背景",     page: "候選窗", keywords: "透明度 對齊 偏移"),
    .init(title: "橫向候選",       page: "候選窗", keywords: "橫向 horizontal"),
    .init(title: "高對比",         page: "候選窗", keywords: "對比 contrast"),
    // 模式提示
    .init(title: "切入提示",       page: "模式提示", keywords: "提示 toast hud 中 A"),
    .init(title: "提示字體／字級", page: "模式提示", keywords: "字體 圓體 明體 字級"),
    .init(title: "提示透明度",     page: "模式提示", keywords: "透明度 opacity"),
    .init(title: "提示字色／描邊", page: "模式提示", keywords: "字色 描邊 stroke 字幕"),
    // 介面
    .init(title: "介面外觀",       page: "介面", keywords: "深色 淺色 自動 dark light appearance"),
    .init(title: "除錯記錄",       page: "介面", keywords: "debug log 記錄"),
    // 說明 / 關於
    .init(title: "使用方法",       page: "說明", keywords: "說明 教學 help"),
    .init(title: "快捷鍵速查",     page: "說明", keywords: "快捷鍵 shortcut 命令"),
    .init(title: "版本與授權",     page: "關於", keywords: "版本 授權 license about"),
]

struct ContentView: View {
    @Bindable var store: PrefsStore
    @State private var selection: Int? = 0
    @State private var query = ""

    /// .preferredColorScheme 解析後的實際深淺（auto 時跟隨系統），
    /// 供側邊欄圖示等需要「實際模式」而非「偏好字串」的判斷用。
    @Environment(\.colorScheme) private var resolvedScheme

    private var colorScheme: ColorScheme? {
        switch store.appearanceMode {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some View {
        Group {
            if store.hasSeenWelcome {
                mainView
            } else {
                WelcomeView { store.hasSeenWelcome = true }
            }
        }
        .preferredColorScheme(colorScheme)
    }

    /// 搜尋命中＋解析出的目標 tag（page 對不到本 build 的 NavItem 就隱藏）
    private var hits: [(SettingHit, Int)] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return settingIndex.compactMap { hit in
            guard (hit.title + " " + hit.keywords).localizedCaseInsensitiveContains(q),
                  let tag = navItems.first(where: { $0.title == hit.page })?.tag
            else { return nil }
            return (hit, tag)
        }
    }

    // 系統設定式格局：側邊欄分頁 + 頂部搜尋 + 右側置中限寬內容（SettingsPage）。
    // columnVisibility 綁定 .constant(.all)：側邊欄是主導覽不可收起——
    // macOS 26 把切換鈕塞進 titlebar accessory，.toolbar(removing:) 攔不到；
    // 常數綁定讓 NSV 根本不產生收起 affordance（按鈕連同材質一起消失）。
    private var mainView: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            VStack(spacing: 0) {
                // 固定不透明搜尋欄：佔欄頂版面，清單從其下方開始——
                // 不用 .searchable(.sidebar)：它是浮層，滾動時項目鑽進半透明區域選不到。
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜尋設定", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .modifier(SearchSurface(glass: store.visualEffects == "full"))
                .padding(.horizontal, 10).padding(.vertical, 8)
                Divider()
                List(selection: $selection) {
                    if query.isEmpty {
                        ForEach(navItems) { item in
                            sidebarItem(item).tag(item.tag)
                        }
                    } else {
                        ForEach(hits, id: \.0.id) { hit, tag in
                            Button { selection = tag; query = "" } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(hit.title).font(Typo.body)
                                    Text(hit.page).font(Typo.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .tag(tag)
                        }
                        if hits.isEmpty {
                            Text("找不到「\(query)」")
                                .font(Typo.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            detailView(for: selection ?? 0)
        }
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 920, minHeight: 600)
        .onAppear { clampSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .selectPrefsTab)) { note in
            if let idx = note.object as? Int { selection = idx; clampSelection() }
        }
    }

    /// 側邊欄項目：淺色＝系統設定式彩色圓角圖示；深色＝同色描邊圖示無底色
    /// （深色下彩色底+白字小圖不易辨識，描邊圖示對比更高）。
    private func sidebarItem(_ item: NavItem) -> some View {
        Label {
            Text(item.title)
        } icon: {
            if resolvedScheme == .dark {
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(item.color)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: item.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(item.color))
            }
        }
    }

    @ViewBuilder
    private func detailView(for tag: Int) -> some View {
        #if !MINIMAL
        switch tag {
        case 0:  InputTab(store: store)
        case 1:  SwitchTab(store: store)
        case 2:  EnglishTab(store: store)
        case 3:  SuggestionTab(store: store)
        case 4:  GeneralDomainsTab(store: store)
        case 5:  ProDomainsTab(store: store)
        case 6:  ShortcutTab()
        case 7:  CandidateTab(store: store)
        case 8:  ToastTab(store: store)
        case 9:  InterfaceTab(store: store)
        case 10: HelpTab()
        default: AboutTab()
        }
        #else
        switch tag {
        case 0: InputTab(store: store)
        case 1: SwitchTab(store: store)
        case 2: EnglishTab(store: store)
        case 3: ShortcutTab()
        case 4: CandidateTab(store: store)
        case 5: ToastTab(store: store)
        case 6: InterfaceTab(store: store)
        case 7: HelpTab()
        default: AboutTab()
        }
        #endif
    }

    /// MINIMAL 版頁數較少：selection 越界時夾回合法範圍
    private func clampSelection() {
        #if MINIMAL
        let maxTag = 8
        #else
        let maxTag = 11
        #endif
        if (selection ?? 0) > maxTag { selection = 0 }
    }
}
