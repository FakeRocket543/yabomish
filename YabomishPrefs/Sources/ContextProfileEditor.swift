import SwiftUI

struct ContextProfileEditor: View {
    let profile: ContextProfile
    let isActive: Bool
    var onSave: (ContextProfile) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var icon: String = ""
    @State private var inputMode: String = "t"
    @State private var regionVariant: String = "tw"
    @State private var suggestEnabled: Bool = true
    @State private var suggestStrategy: String = "general"
    @State private var charSuggest: Bool = true
    @State private var wordCorpus: String = "wiki"
    @State private var fuzzyMatch: Bool = true
    @State private var autoCommit: Bool = false
    @State private var enabledDomains: Set<String> = []

    private static let modeOptions: [(String, String)] = [
        ("t", "繁中"), ("s", "簡中"), ("sp", "速打"), ("sl", "慢打"),
        ("ts", "繁→簡"), ("st", "簡→繁"), ("j", "日文"),
    ]
    private static let regionOptions: [(String, String)] = [("tw", "台灣"), ("cn", "中國")]
    private static let strategyOptions: [(String, String)] = [("general", "一般"), ("domain", "專業")]
    private static let corpusOptions: [(String, String)] = [("wiki", "維基百科"), ("moedict", "萌典"), ("news", "新聞")]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("編輯語境 — \(icon) \(name)").font(Typo.h2)

            GroupBox("基本") {
                HStack {
                    Text("圖示"); TextField("emoji", text: $icon).frame(width: 50)
                    Spacer(minLength: 20)
                    Text("名稱"); TextField("名稱", text: $name).frame(width: 120)
                }
                HStack { Text("命令碼"); Text(profile.code).font(Typo.bodyMono).foregroundStyle(.secondary) }
            }

            GroupBox("輸入") {
                HStack {
                    Text("模式"); Picker("", selection: $inputMode) {
                        ForEach(Self.modeOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }.frame(width: 100)
                    Spacer(minLength: 20)
                    Text("地區"); Picker("", selection: $regionVariant) {
                        ForEach(Self.regionOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }.frame(width: 80)
                }
                HStack {
                    Toggle("模糊匹配", isOn: $fuzzyMatch)
                    Spacer(minLength: 20)
                    Toggle("自動送字", isOn: $autoCommit)
                }
            }

            GroupBox("聯想") {
                HStack {
                    Toggle("聯想系統", isOn: $suggestEnabled)
                    Spacer(minLength: 20)
                    Toggle("字級聯想", isOn: $charSuggest)
                }
                HStack {
                    Text("策略"); Picker("", selection: $suggestStrategy) {
                        ForEach(Self.strategyOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }.frame(width: 80)
                    Spacer(minLength: 20)
                    Text("詞級語料"); Picker("", selection: $wordCorpus) {
                        ForEach(Self.corpusOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }.frame(width: 100)
                }
            }

            GroupBox("詞庫") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(DomainData.allDomains) { d in
                            Toggle(isOn: Binding(
                                get: { enabledDomains.contains(d.id) },
                                set: { if $0 { enabledDomains.insert(d.id) } else { enabledDomains.remove(d.id) } }
                            )) {
                                HStack(spacing: 6) {
                                    Image(systemName: d.icon).frame(width: 16)
                                    Text(d.label).font(Typo.body)
                                    Text(d.desc).font(Typo.caption).foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(height: 180)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("儲存") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { load() }
    }

    private func load() {
        name = profile.name
        icon = profile.icon
        inputMode = profile.inputMode
        regionVariant = profile.regionVariant
        suggestEnabled = profile.suggestEnabled
        suggestStrategy = profile.suggestStrategy
        charSuggest = profile.charSuggest
        wordCorpus = profile.wordCorpus
        fuzzyMatch = profile.fuzzyMatch
        autoCommit = profile.autoCommit
        enabledDomains = Set(profile.domainEnabled.filter(\.value).map(\.key))
    }

    private func save() {
        var p = profile
        p.name = name
        p.icon = icon
        p.inputMode = inputMode
        p.regionVariant = regionVariant
        p.suggestEnabled = suggestEnabled
        p.suggestStrategy = suggestStrategy
        p.charSuggest = charSuggest
        p.wordCorpus = wordCorpus
        p.fuzzyMatch = fuzzyMatch
        p.autoCommit = autoCommit
        p.domainOrder = DomainData.allDomains.map(\.id).filter { enabledDomains.contains($0) }
        p.domainEnabled = Dictionary(uniqueKeysWithValues: DomainData.allDomains.map { ($0.id, enabledDomains.contains($0.id)) })
        p.save()
        onSave(p)
        dismiss()
    }
}
