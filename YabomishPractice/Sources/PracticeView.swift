import SwiftUI

/// 設計 token（與 YabomishPrefs 同風格，獨立定義）
private enum Typo {
    static let h2 = Font.system(size: 17, weight: .bold)
    static let body = Font.system(size: 14)
    static let caption = Font.system(size: 12)
    static let mono = Font.system(size: 15, weight: .medium, design: .monospaced)
    static let accent = Color.accentColor
}

struct PracticeRootView: View {
    @State private var engine = DrillEngine()
    @State private var loadError: String?
    @State private var source: DrillEngine.Source = .common
    @State private var roundSize = 20
    @State private var activeSession: PracticeSession?
    @State private var recent: [SessionRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let err = loadError {
                Spacer()
                Text("⚠️ \(err)").font(Typo.body).foregroundStyle(.orange)
                Spacer()
            } else if activeSession != nil {
                PracticeSessionView(initial: activeSession!) {
                    activeSession = nil
                    recent = StatsStore.recent()
                }
            } else {
                menu
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if !engine.tableLoaded { loadError = engine.load() }
            recent = StatsStore.recent()
        }
    }

    // MARK: - 首頁選單

    private var menu: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("打字練習", systemImage: "keyboard.badge.eye").font(Typo.h2)
            Text("看打練習：畫面出字，輸入嘸蝦米碼按 Enter 送出。題目由你自己的拆碼表即時生成，不連網。")
                .font(Typo.body).foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Picker("題源", selection: $source) {
                    ForEach(DrillEngine.Source.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 290)

                Picker("題數", selection: $roundSize) {
                    Text("10").tag(10)
                    Text("20").tag(20)
                    Text("50").tag(50)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)

                Button("開始") { start() }
                    .buttonStyle(.borderedProminent)
            }

            switch source {
            case .common:
                Text("依公共語料出現頻率取前 200 常用字——日常覆蓋率最高的字先熟。")
                    .font(Typo.caption).foregroundStyle(.tertiary)
            case .weak:
                Text("從查字歷史取最近查過的字——這些就是你「不會拆碼的字」，直接當複習題。")
                    .font(Typo.caption).foregroundStyle(.tertiary)
            case .random:
                Text("全表隨機——測真實覆蓋率，偶爾會遇到罕用字。")
                    .font(Typo.caption).foregroundStyle(.tertiary)
            }

            if !recent.isEmpty {
                Divider().padding(.vertical, 4)
                Text("最近成績").font(Typo.caption).foregroundStyle(.secondary)
                ForEach(recent) { r in
                    HStack {
                        Text(r.mode).font(Typo.mono).frame(width: 50, alignment: .leading)
                        Text(String(format: "%.1f 字/分", r.kpm)).font(Typo.body)
                        Text(String(format: "準確率 %.0f%%", r.accuracy * 100))
                            .font(Typo.caption)
                            .foregroundStyle(r.accuracy >= 0.95 ? Typo.accent : .primary)
                        Spacer()
                        Text(dateText(r.ts)).font(Typo.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func start() {
        let (items, err) = engine.makeRound(source: source, count: roundSize)
        if let err { loadError = err; return }
        loadError = nil
        activeSession = PracticeSession(mode: source.rawValue, items: items)
    }

    private func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: d)
    }
}

// MARK: - 一輪練習

struct PracticeSession: Identifiable {
    let id = UUID()
    let mode: String
    let items: [DrillEngine.Item]
    var index = 0
    var attempts = 0
    var correct = 0
    var startedAt = Date()

    var finished: Bool { index >= items.count }
    var currentItem: DrillEngine.Item? { index < items.count ? items[index] : nil }
    var seconds: Double { Date().timeIntervalSince(startedAt) }
}

struct WrongAnswer: Identifiable {
    let id = UUID()
    let char: String
    let typed: String
    let codes: [String]
}

struct PracticeSessionView: View {
    let initial: PracticeSession
    let onExit: () -> Void

    @State private var s: PracticeSession
    @State private var input = ""
    @State private var flash: Color?
    @State private var lastWrong: WrongAnswer?
    @State private var wrongLog: [WrongAnswer] = []
    @State private var saved = false
    @FocusState private var focused: Bool

    init(initial: PracticeSession, onExit: @escaping () -> Void) {
        self.initial = initial
        self.onExit = onExit
        _s = State(initialValue: initial)
    }

    var body: some View {
        Group {
            if s.finished { result } else { drilling }
        }
        .onAppear { focused = true }
    }

    // MARK: 練習中

    private var drilling: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("\(s.mode) · 第 \(s.index + 1)/\(s.items.count) 字")
                    .font(Typo.caption).foregroundStyle(.secondary)
                Spacer()
                Text("對 \(s.correct) · 錯 \(wrongLog.count)")
                    .font(Typo.mono)
                    .foregroundStyle(wrongLog.isEmpty ? Typo.accent : .orange)
                Button("結束") { onExit() }.buttonStyle(.link)
            }
            ProgressView(value: Double(s.index), total: Double(s.items.count))

            Group {
                if let item = s.currentItem {
                    Text(item.char)
                        .font(.system(size: 88, weight: .medium))
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 10) {
                TextField("輸入碼後按 Enter", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 22, design: .monospaced))
                    .focused($focused)
                    .onSubmit(submit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(flash ?? .clear, lineWidth: 2.5)
                            .animation(.easeOut(duration: 0.35), value: flash)
                    )
                Button("送出") { submit() }.disabled(input.isEmpty)
                Button("跳過") { skip() }
            }

            if let w = lastWrong {
                Text("上題「\(w.char)」正確碼：\(w.codes.joined(separator: " / "))")
                    .font(Typo.mono).foregroundStyle(.red)
            }
        }
    }

    // MARK: 結算

    private var result: some View {
        let record = SessionRecord(ts: Date(), mode: s.mode, total: s.attempts,
                                   correct: s.correct, seconds: s.seconds)
        return VStack(alignment: .leading, spacing: 14) {
            Text("本輪完成").font(Typo.h2)
            HStack(spacing: 28) {
                metric(String(format: "%.1f", record.kpm), "字／分鐘")
                metric(String(format: "%.0f%%", record.accuracy * 100), "準確率")
                metric(String(format: "%.0f 秒", record.seconds), "用時")
                metric("\(s.correct)/\(s.attempts)", "答對")
            }
            if !wrongLog.isEmpty {
                Divider().padding(.vertical, 2)
                Text("待加強（\(wrongLog.count) 字）").font(Typo.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(wrongLog) { w in
                            HStack(spacing: 10) {
                                Text(w.char).font(.system(size: 17))
                                Text("→ " + w.codes.joined(separator: " / "))
                                    .font(Typo.mono).foregroundStyle(Typo.accent)
                                if !w.typed.isEmpty {
                                    Text("(你打了 \(w.typed))").font(Typo.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
            }
            HStack {
                if saved { Text("成績已記錄").font(Typo.caption).foregroundStyle(.green) }
                Spacer()
                Button("回選單") { onExit() }.buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            if !saved { StatsStore.append(record); saved = true }
        }
    }

    private func metric(_ v: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 26, weight: .semibold, design: .rounded))
            Text(label).font(Typo.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: 作答

    private func submit() {
        guard let item = s.currentItem else { return }
        let typed = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !typed.isEmpty else { return }
        if item.codes.contains(typed) {
            advance(correct: true)
            flash = .green
        } else {
            let w = WrongAnswer(char: item.char, typed: typed, codes: item.codes)
            wrongLog.append(w)
            lastWrong = w
            advance(correct: false)
            flash = .red
        }
        input = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { self.flash = nil }
        focused = true
    }

    private func skip() {
        guard let item = s.currentItem else { return }
        let w = WrongAnswer(char: item.char, typed: "", codes: item.codes)
        wrongLog.append(w)
        lastWrong = w
        advance(correct: false)
        input = ""
        focused = true
    }

    private func advance(correct ok: Bool) {
        s.attempts += 1
        if ok { s.correct += 1 }
        s.index += 1
    }
}
