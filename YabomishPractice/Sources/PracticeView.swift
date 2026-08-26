import SwiftUI

/// 設計 token（與 YabomishPrefs 同風格，獨立定義）
private enum Typo {
    static let h2 = Font.system(size: 17, weight: .bold)
    static let body = Font.system(size: 14)
    static let caption = Font.system(size: 12)
    static let mono = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let accent = Color.accentColor
}

struct PracticeRootView: View {
    @State private var engine = DrillEngine()
    @State private var loadError: String?
    @State private var source: DrillEngine.Source = .common
    @State private var roundSize = 20
    @State private var activeSession: PracticeSession?
    @State private var activeArticle: ArticleSession?
    @State private var recent: [SessionRecord] = []
    @State private var showArticleSheet = false
    @State private var roundError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let err = loadError {
                Spacer()
                Text("⚠️ \(err)\n請確認已安裝 Yabomish 輸入法並匯入字表後重新開啟本程式。")
                    .font(Typo.body).foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
                Spacer()
            } else if let a = activeArticle {
                PracticeSessionView(initial: a.session, engine: engine) {
                    activeArticle = nil
                    recent = StatsStore.recent()
                }
            } else if let s = activeSession {
                PracticeSessionView(initial: s, engine: engine) {
                    activeSession = nil
                    recent = StatsStore.recent()
                }
            } else {
                menu
            }
        }
        .onChange(of: source) { _, _ in roundError = nil }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if !engine.tableLoaded { loadError = engine.load() }
            recent = StatsStore.recent()
        }
        .sheet(isPresented: $showArticleSheet) {
            ArticleInputView(engine: engine) { session in
                showArticleSheet = false
                activeArticle = ArticleSession(session: session)
            }
            .frame(width: 520, height: 420)
        }
    }

    // MARK: - 首頁選單

    private var menu: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "keyboard")
                    .font(.system(size: 42))
                    .foregroundStyle(Typo.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("打字練習").font(Typo.h2)
                    Text("看打練習：畫面出字，輸入嘸蝦米碼按 **空白鍵** 送出（Enter 也可以）。題目由你自己的拆碼表即時生成，不連網。")
                        .font(Typo.body).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Picker("題源", selection: $source) {
                    ForEach(DrillEngine.Source.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 380)

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

            HStack(spacing: 12) {
                Button("自訂文章⋯") { showArticleSheet = true }
                Text("貼上任意文字，依原文順序逐字看打；打錯的字自動收進弱點池")
                    .font(Typo.caption).foregroundStyle(.tertiary)
            }

            sourceHint
            if let err = roundError {
                Text("⚠️ \(err)").font(Typo.caption).foregroundStyle(.orange)
            }


            if !recent.isEmpty {
                Divider().padding(.vertical, 6)
                Text("最近成績").font(Typo.caption).foregroundStyle(.secondary)
                ForEach(recent) { r in
                    HStack {
                        Text(r.mode).font(Typo.mono).frame(width: 72, alignment: .leading)
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

    @ViewBuilder
    private var sourceHint: some View {
        switch source {
        case .common:
            Text("依公共語料出現頻率取前 200 常用字——日常覆蓋率最高的字先熟。")
                .font(Typo.caption).foregroundStyle(.tertiary)
        case .short:
            Text("最短碼在一、二碼的高頻字——練簡碼手感，速度最快的來源。")
                .font(Typo.caption).foregroundStyle(.tertiary)
        case .weak:
            Text("查字歷史 ∪ 練習錯字收集——這些就是你「不會拆碼的字」，直接當複習題。")
                .font(Typo.caption).foregroundStyle(.tertiary)
        case .random:
            Text("全表隨機——測真實覆蓋率，偶爾會遇到罕用字。")
                .font(Typo.caption).foregroundStyle(.tertiary)
        }
    }


    private func start() {
        let (items, err) = engine.makeRound(source: source, count: roundSize)
        if let err {
            roundError = err   // 暫時性錯誤（如弱點池尚空）——inline 顯示，不覆蓋選單
            return
        }
        roundError = nil
        activeSession = PracticeSession(mode: source.rawValue, items: items)
    }

    private func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: d)
    }
}

/// 自訂文章工作階段標記（與單元題源區分）
struct ArticleSession { let session: PracticeSession }

// MARK: - 自訂文章輸入

struct ArticleInputView: View {
    let engine: DrillEngine
    let onStart: (PracticeSession) -> Void
    @State private var text = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自訂文章").font(Typo.h2)
            Text("貼上想練的文字（上限 200 字，表外字自動跳過）。依原文順序逐字看打。")
                .font(Typo.caption).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(Typo.body)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
                .frame(maxHeight: .infinity)
            if let err = error {
                Text("⚠️ \(err)").font(Typo.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("開始練習") { begin() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .interactiveDismissDisabled(!text.isEmpty)
    }

    private func begin() {
        let trimmed = String(text.prefix(400)) // 上限放寬收錄，實際題數由 cap 控制
        let (items, skipped, err) = engine.makeRoundFromArticle(trimmed)
        if let err { error = err; return }
        let mode = skipped > 0 ? "文章（跳過 \(skipped) 表外字）" : "文章"
        onStart(PracticeSession(mode: mode, items: items))
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
    let engine: DrillEngine
    let onExit: () -> Void

    @State private var s: PracticeSession
    @State private var input = ""
    @State private var flash: Color?
    @State private var flashClear: DispatchWorkItem?   // 可取消的清除計時——快速連打時新回饋先取消舊清除
    @State private var lastWrong: WrongAnswer?
    @State private var wrongLog: [WrongAnswer] = []
    @State private var hintShownFor: Int?
    @State private var hintsUsed = 0
    @State private var saved = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(initial: PracticeSession, engine: DrillEngine, onExit: @escaping () -> Void) {
        self.initial = initial
        self.engine = engine
        self.onExit = onExit
        _s = State(initialValue: initial)
    }

    var body: some View {
        Group {
            if s.finished { result } else { drilling }
        }
        .onAppear {
            // 即按即開始：進入練習立刻搶焦點，0.12s 後補一次（等 window 成為 key）
            DispatchQueue.main.async { self.focused = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.focused = true }
        }
        .onDisappear { flashClear?.cancel() }
    }

    /// 上下文／佇列預覽：當前字前後各取若干，文章模式即原文語境，單元模式即接續預覽
    private var contextStrip: some View {
        let before = max(0, s.index - 4)
        let after = min(s.items.count, s.index + 7)
        return HStack(spacing: 2) {
            if before > 0 { Text("⋯").font(Typo.caption).foregroundStyle(.tertiary) }
            ForEach(before..<after, id: \.self) { i in
                Text(s.items[i].char)
                    .font(.system(size: i == s.index ? 20 : 14, weight: i == s.index ? .bold : .regular))
                    .foregroundStyle(i == s.index ? Typo.accent : (i < s.index ? Color.secondary.opacity(0.6) : .secondary))
                    .frame(minWidth: 22)
            }
            if after < s.items.count { Text("⋯").font(Typo.caption).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity)
    }
    private var drilling: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(s.mode) · 第 \(s.index + 1)/\(s.items.count) 字")
                    .font(Typo.caption).foregroundStyle(.secondary)
                Spacer()
                Text("對 \(s.correct) · 錯 \(wrongLog.count)")
                    .font(Typo.mono)
                    .foregroundStyle(wrongLog.isEmpty ? Typo.accent : .orange)
                Button("結束") { finishEarly() }.buttonStyle(.link)
            }

            ProgressView(value: Double(s.index), total: Double(s.items.count))
                .tint(Typo.accent)

            contextStrip

            // 大字卡：material 底＋對錯閃色＋換題縮放過場
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.07), radius: 6, y: 2)
                RoundedRectangle(cornerRadius: 16)
                    .fill(flash.map { $0.opacity(0.16) } ?? .clear)
                RoundedRectangle(cornerRadius: 16)
                    .stroke(flash ?? .clear, lineWidth: 2)
                if let item = s.currentItem {
                    Text(item.char)
                        .font(.system(size: 92, weight: .medium))
                        .minimumScaleFactor(0.5)
                        .padding(24)
                        .id(s.index)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            HStack(spacing: 10) {
                TextField("輸入碼後按 空白鍵 送出", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 22, design: .monospaced))
                    .focused($focused)
                    .onSubmit(submit)
                    .onKeyPress(.space) { submit(); return .handled }
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(flash ?? .clear, lineWidth: 2.5)
                            .animation(.easeOut(duration: 0.35), value: flash)
                    )
                Button("送出 ␣") { submit() }
                    .disabled(input.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Button("跳過") { skip() }
                Button("提示") { revealHint() }
                    .disabled(hintShownFor == s.index)
            }

            HStack(spacing: 14) {
                if let w = lastWrong {
                    Text("上題「\(w.char)」正確碼：\(w.codes.joined(separator: " / "))")
                        .font(Typo.mono).foregroundStyle(.red)
                } else if let hint = hintText {
                    Text(hint).font(Typo.mono).foregroundStyle(.orange)
                }
                Spacer()
            }
            .frame(height: 20)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: s.index)
    }

    private var hintText: String? {
        guard hintShownFor == s.index, let item = s.currentItem, let first = item.codes.first else { return nil }
        return "提示：「\(item.char)」的第一碼是 \(first)"
    }

    private func revealHint() {
        guard hintShownFor != s.index, s.currentItem != nil else { return }
        hintShownFor = s.index
        hintsUsed += 1
        DispatchQueue.main.async { self.focused = true }
    }

    // MARK: 結算

    private var result: some View {
        let record = SessionRecord(ts: Date(), mode: s.mode, total: s.attempts,
                                   correct: s.correct, seconds: s.seconds)
        return VStack(alignment: .leading, spacing: 14) {
            Text("本輪完成").font(Typo.h2)
            HStack(spacing: 12) {
                metric(String(format: "%.1f", record.kpm), "字／分鐘")
                metric(String(format: "%.0f%%", record.accuracy * 100), "準確率")
                metric(String(format: "%.0f 秒", record.seconds), "用時")
                metric("\(s.correct)/\(s.attempts)", "答對")
                if hintsUsed > 0 { metric("\(hintsUsed)", "用提示") }
            }
            if !wrongLog.isEmpty {
                Divider().padding(.vertical, 6)
                Text("待加強（\(wrongLog.count) 字）— 已自動收進弱點池，下輪「弱點字」優先出現")
                    .font(Typo.caption).foregroundStyle(.secondary)
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
            guard !saved else { return }
            if s.attempts > 0 { saved = StatsStore.append(record) }
            engine.collectWrong(wrongLog.map(\.char))
            saved = true   // 零作答不寫檔，但避免重入
        }
    }

    private func metric(_ v: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Typo.accent)
            Text(label).font(Typo.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
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
        scheduleFlashClear()
        DispatchQueue.main.async { self.focused = true }
    }

    private func skip() {
        guard let item = s.currentItem else { return }
        let w = WrongAnswer(char: item.char, typed: "", codes: item.codes)
        wrongLog.append(w)
        lastWrong = w
        advance(correct: false)
        input = ""
        DispatchQueue.main.async { self.focused = true }
    }

    private func scheduleFlashClear() {
        flashClear?.cancel()
        let job = DispatchWorkItem { self.flash = nil }
        flashClear = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36, execute: job)
    }

    /// 提前結束：剩餘未作答字直接略過——不計 attempts、不進弱點池，僅就已作答部分結算
    private func finishEarly() {
        s.index = s.items.count
    }


    private func advance(correct ok: Bool) {
        s.attempts += 1
        if ok { s.correct += 1 }
        s.index += 1
    }
}
