// controller 層 e2e:實體化 YabomishInputController + mock client,
// 以合成 NSEvent 驗證 issue #18 中英切換鍵邏輯(shift/capslock/both/none)
// 與 secure-input 靜音旗標。
// 編譯:全部 YabomishIM/Sources + 本檔 → 獨立 binary(不需安裝/啟用 IM)。
import Cocoa
import InputMethodKit
import IOKit

var passed = 0, failed = 0
func check(_ c: Bool, _ m: String) {
    if c { passed += 1; print("PASS \(m)") }
    else { failed += 1; print("FAIL \(m)") }
}

/// IMKTextInput 全部 required(無 @optional)——受測路徑用的記錄值,其餘 stub。
final class MockClient: NSObject, IMKTextInput {
    var inserted: [String] = []
    var marked: String = ""
    var inputModeSet: String? = nil

    func insertText(_ string: Any!, replacementRange: NSRange) {
        marked = ""   // 真實 IMK：insertText 以送出文字取代 marked 組字
        if let s = string as? String { inserted.append(s) }
        else if let s = string as? NSAttributedString { inserted.append(s.string) }
    }
    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        marked = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
    }
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func markedRange() -> NSRange {
        // 真實 client：有組字時回組字範圍；無組字時 location=NSNotFound、length=0。
        // controller 的英文聯想以 length==engPrefix.count 偵測 marked 是否被外部收編。
        NSRange(location: marked.isEmpty ? NSNotFound : 0, length: marked.count)
    }
    func attributedSubstring(from range: NSRange) -> NSAttributedString! { nil }
    func length() -> Int { 0 }
    func characterIndex(for point: NSPoint, tracking mappingMode: Int, inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { NSNotFound }
    func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! { nil }
    func validAttributesForMarkedText() -> [Any]! { [] }
    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
    func selectMode(_ modeIdentifier: String!) { inputModeSet = modeIdentifier }
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { "com.yabomish.e2e" }
    func windowLevel() -> Int32 { 0 }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "e2e-client" }
    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { nil }
    func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect { .zero }
}

func flagsEvent(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags, ts: TimeInterval? = nil) -> NSEvent {
    NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags,
                     timestamp: ts ?? ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                     context: nil, characters: "", charactersIgnoringModifiers: "",
                     isARepeat: false, keyCode: keyCode)!
}
func keyEvent(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                     context: nil, characters: "", charactersIgnoringModifiers: "",
                     isARepeat: false, keyCode: keyCode)!
}

func newController() -> (YabomishInputController, MockClient) {
    let c = YabomishInputController(server: nil, delegate: nil, client: nil)!
    let m = MockClient()
    return (c, m)
}

func setToggle(_ v: String) {
    YabomishPrefs.defaults.set(v, forKey: "englishToggleKey")
    // setter 走 defaults.set + refreshSnapshot;直接寫 key 也要 refresh → 走公開 setter
    YabomishPrefs.englishToggleKey = v
}

let devID = Bundle.main.bundleIdentifier ?? "com.yabomishim.inputmethod.YabomishIM"

// ─── E1: pref=shift — Shift 快按切英文(回歸)───
do {
    setToggle("shift")
    let (c, m) = newController()
    let t0 = ProcessInfo.processInfo.systemUptime
    _ = c.handleWithNewEngine(flagsEvent(56, [.shift], ts: t0), client: m)
    _ = c.handleWithNewEngine(flagsEvent(56, [], ts: t0 + 0.1), client: m)
    check(c.engine.isEnglishMode == true, "E1a shift 快按 → 英文模式")

    _ = c.handleWithNewEngine(flagsEvent(56, [.shift], ts: t0 + 0.2), client: m)
    _ = c.handleWithNewEngine(flagsEvent(56, [], ts: t0 + 0.3), client: m)
    check(c.engine.isEnglishMode == false, "E1c shift 快按 → 回中文")
}

// ─── E1': shift 當修飾鍵用過後放開不觸發(回歸)───
do {
    setToggle("shift")
    let (c, m) = newController()
    let t0 = ProcessInfo.processInfo.systemUptime
    _ = c.handleWithNewEngine(flagsEvent(56, [.shift], ts: t0), client: m)
    _ = c.handleWithNewEngine(keyEvent(0, [.shift]), client: m)   // Shift 按住+a → 暫時英文 'a'
    _ = c.handleWithNewEngine(flagsEvent(56, [], ts: t0 + 0.1), client: m)
    check(c.engine.isEnglishMode == false, "E1' shift 當修飾鍵用 → 快按不觸發")
    check(m.inserted.last == "a", "E1' shift+a 暫時英文 → 'a'")
}

// ─── E2: pref=capslock — caps 按一下切、再按切回 ───
do {
    setToggle("capslock")
    let (c, m) = newController()
    _ = c.handleWithNewEngine(flagsEvent(57, [.capsLock]), client: m)   // →ON
    check(c.engine.isEnglishMode == true, "E2a caps →ON → 英文模式")

    _ = c.handleWithNewEngine(flagsEvent(57, [.capsLock]), client: m)   // 再次 →ON
    check(c.engine.isEnglishMode == false, "E2c caps 再按 → 回中文")

    // flag=false 事件(解鎖/回聲)不觸發
    _ = c.handleWithNewEngine(flagsEvent(57, [.capsLock]), client: m)
    check(c.engine.isEnglishMode == true, "E2d caps →ON → 英文")
    _ = c.handleWithNewEngine(flagsEvent(57, []), client: m)            // →OFF(回聲)
    check(c.engine.isEnglishMode == true, "E2e flag=false 事件不觸發")
}

// ─── E3: pref=capslock — Shift 快按不觸發 ───
do {
    setToggle("capslock")
    let (c, m) = newController()
    let t0 = ProcessInfo.processInfo.systemUptime
    _ = c.handleWithNewEngine(flagsEvent(56, [.shift], ts: t0), client: m)
    _ = c.handleWithNewEngine(flagsEvent(56, [], ts: t0 + 0.1), client: m)
    check(c.engine.isEnglishMode == false, "E3 shift 快按在 capslock 模式不觸發")
}

// ─── E4: pref=capslock — Shift 修飾鍵功能健在 ───
do {
    setToggle("capslock")
    let (c, m) = newController()
    _ = c.handleWithNewEngine(keyEvent(0, [.shift]), client: m)   // Shift 按住+a 暫時英文
    check(m.inserted.last == "a", "E4a capslock 模式 Shift+a → 'a'")
    // Shift+8 組字中萬用碼:進入組字再按
    _ = c.handleWithNewEngine(keyEvent(0), client: m)             // 'a' 進組字
    _ = c.handleWithNewEngine(keyEvent(28, [.shift]), client: m)  // Shift+8 萬用碼
    check(true, "E4b Shift+8 萬用碼路徑不當機")
}

// ─── E5: pref=both — 兩鍵各自切 ───
do {
    setToggle("both")
    let (c, m) = newController()
    let t0 = ProcessInfo.processInfo.systemUptime
    _ = c.handleWithNewEngine(flagsEvent(56, [.shift], ts: t0), client: m)
    _ = c.handleWithNewEngine(flagsEvent(56, [], ts: t0 + 0.1), client: m)
    check(c.engine.isEnglishMode == true, "E5a both: shift 快按切英文")
    _ = c.handleWithNewEngine(flagsEvent(57, [.capsLock]), client: m)
    check(c.engine.isEnglishMode == false, "E5b both: caps 切回中文")
}

// ─── E6: capsLock flag 遮罩 — latched 狀態不造成大寫 ───
do {
    setToggle("capslock")
    YabomishPrefs.englishSuggest = false  // 英文聯想開著時字母進組字不直放；此項驗 caps 遮罩
    let (c, m) = newController()
    // 模擬 flag 殘留 ON(例如 forceOff 失敗的環境):shift+a 應仍是大寫 A(shift 語意)
    // 而單純 .capsLock flag 不該把暫時英文字母變大寫 — 但暫時英文路徑本來就要 shift,
    // 所以這裡驗證英文模式內 wantShift 的遮罩:
    _ = c.handleWithNewEngine(flagsEvent(57, [.capsLock]), client: m)  // 進英文
    _ = c.handleWithNewEngine(keyEvent(0, [.capsLock]), client: m)     // 殘留 caps flag 的 'a'
    check(m.inserted.last == "a", "E6a 殘留 .capsLock flag 不產生大寫")
    _ = c.handleWithNewEngine(keyEvent(0, [.capsLock, .shift]), client: m)
    check(m.inserted.last == "A", "E6b caps flag + 實體 shift → 仍大寫(shift 決定)")

    setToggle("shift")
    let (c2, m2) = newController()
    // pref=shift:caps flag 保留原本大寫語意(回歸)
    _ = c2.handleWithNewEngine(flagsEvent(56, [.shift]), client: m2)
    _ = c2.handleWithNewEngine(flagsEvent(56, []), client: m2)
    _ = c2.handleWithNewEngine(keyEvent(0, [.capsLock]), client: m2)   // 英文模式 caps+a
    check(m2.inserted.last == "A", "E6c pref=shift 時 .capsLock 仍是大寫語意(回歸)")
    YabomishPrefs.englishSuggest = true
}

// ─── E7: pref=none — 兩鍵皆不切、.capsLock 恢復大寫語意 ───
do {
    setToggle("none")
    YabomishPrefs.englishSuggest = false  // 同上：此項驗大小寫語意，不走聯想組字
    let (c, m) = newController()
    let t0 = ProcessInfo.processInfo.systemUptime
    _ = c.handleWithNewEngine(flagsEvent(56, [.shift], ts: t0), client: m)
    _ = c.handleWithNewEngine(flagsEvent(56, [], ts: t0 + 0.1), client: m)
    check(c.engine.isEnglishMode == false, "E7a none: shift 快按不切")
    _ = c.handleWithNewEngine(flagsEvent(57, [.capsLock]), client: m)
    check(c.engine.isEnglishMode == false, "E7b none: caps 不切")
    // none 下 .capsLock flag 恢復大寫語意（需英文模式才看得到字母大小寫差異；
    // 用選單路徑進英文——不經切換鍵）
    c.engine.setEnglishMode(true)
    _ = c.handleWithNewEngine(keyEvent(0, [.capsLock]), client: m)
    check(m.inserted.last == "A", "E7c none: .capsLock flag 恢復大寫語意")
    _ = c.handleWithNewEngine(keyEvent(0), client: m)
    check(m.inserted.last == "a", "E7d none: 無 flag → 小寫")
    YabomishPrefs.englishSuggest = true
}

// ─── E8: secure-input 靜音旗標 ───
do {
    // freqTracker.suppressRecording：被擋的寫入不落庫
    let ft = FreqTracker()
    let before = ft.recentLookups(limit: 50).count
    ft.suppressRecording = true
    ft.record(code: "zz", char: "對")
    ft.recordBigram(prev: "我", char: "對")
    ft.recordLookup(mode: "x", query: "zzq", char: "對", code: "zz")
    ft.pin(code: "zz", chars: ["對"])
    ft.suppressRecording = false
    ft.recordLookup(mode: "x", query: "zzq", char: "對", code: "zz")
    let after = ft.recentLookups(limit: 50).count
    check(after == before + 1, "E8a suppressRecording 擋住全部寫入、放行後正常")

    // allowSecureInput pref 讀寫
    YabomishPrefs.allowSecureInput = true
    check(YabomishPrefs.allowSecureInput == true, "E8b allowSecureInput pref 寫入/讀回")
    YabomishPrefs.allowSecureInput = false
    check(YabomishPrefs.allowSecureInput == false, "E8c allowSecureInput 預設關")
}

// ─── E11: IOHID force-off 真的解鎖 ───
do {
    check(CapsLockControl.available, "E11a IOHID 連線可用")
    CapsLockControl.setLock(true)
    check(CapsLockControl.isLocked() == true, "E11b 設 ON 後 isLocked==true")
    CapsLockControl.forceOff()
    check(CapsLockControl.isLocked() == false, "E11c forceOff 後 isLocked==false")
}

// ─── E12: pref 異常值回落 shift ───
do {
    setToggle("bogus")
    check(YabomishPrefs.englishToggleKey == "shift", "E12 異常值回落 shift")
    setToggle("shift")
}

// ─── E13: HUD 個性化 prefs 讀寫與預設 ───
do {
    check(YabomishPrefs.toastFontStyle == "system", "E13a toastFontStyle 預設 system")
    check(YabomishPrefs.toastTextColor == "#FFFFFF", "E13b toastTextColor 預設白")
    check(YabomishPrefs.toastStroke == false, "E13c toastStroke 預設關")
    check(YabomishPrefs.toastStrokeColor == "#000000", "E13d toastStrokeColor 預設黑")
    for v in ["rounded", "serif", "system"] {
        YabomishPrefs.toastFontStyle = v
        check(YabomishPrefs.toastFontStyle == v, "E13e toastFontStyle=\(v) 寫入/讀回")
    }
    YabomishPrefs.toastTextColor = "#FF8800"
    check(YabomishPrefs.toastTextColor == "#FF8800", "E13f toastTextColor 寫入/讀回")
    YabomishPrefs.toastTextColor = "#FFFFFF"
    YabomishPrefs.toastStroke = true
    check(YabomishPrefs.toastStroke == true, "E13g toastStroke 開啟")
    YabomishPrefs.toastStroke = false
    YabomishPrefs.toastStrokeColor = "#112233"
    check(YabomishPrefs.toastStrokeColor == "#112233", "E13h toastStrokeColor 寫入/讀回")
    YabomishPrefs.toastStrokeColor = "#000000"
}

// ─── E14: 英文聯想（iOS 版移植）───
do {
    // 14a: Trie 前綴搜尋（rank 序）
    let trie = EnglishTrie(words: ["the", "they", "them", "there", "test", "testing"])
    check(trie.search(prefix: "th") == ["the", "they", "them", "there"], "E14a trie prefix 依 rank 序")
    check(trie.search(prefix: "tes") == ["test", "testing"], "E14a2 trie 兩結果")
    check(trie.search(prefix: "zzz").isEmpty, "E14a3 trie 無匹配→空")

    // 14b: UserEnglishDict 增刪查（tmp 目錄隔離）
    let tmpDir = NSTemporaryDirectory() + "e2e-engdict-\(UUID().uuidString.prefix(8))"
    try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
    let dict = UserEnglishDict(dir: tmpDir)
    dict.add("Xyzzy")
    dict.add("Foo")
    check(dict.contains("xyzzy") && dict.contains("foo"), "E14b1 dict add+contains（大小寫無關）")
    check(dict.search(prefix: "x") == ["xyzzy"], "E14b2 dict prefix 搜尋")
    let dict2 = UserEnglishDict(dir: tmpDir)
    check(dict2.contains("xyzzy"), "E14b3 dict 持久化（重建讀回）")
    dict2.remove("xyzzy")
    check(!dict2.contains("xyzzy"), "E14b4 dict remove")
    dict2.removeAll()
    check(dict2.count == 0, "E14b5 dict removeAll")
    try? FileManager.default.removeItem(atPath: tmpDir)

    // 14c: pref 讀寫（無鍵時 Prefs.swift 的 `as? Bool ?? true` 給預設開）
    YabomishPrefs.englishSuggest = false
    check(YabomishPrefs.englishSuggest == false, "E14c englishSuggest 寫關/讀回")
    YabomishPrefs.englishSuggest = true
    check(YabomishPrefs.englishSuggest == true, "E14c2 englishSuggest 寫開/讀回")

    // 14d: controller 全路徑 — 注入小詞表後走合成按鍵
    EnglishTrie.shared = EnglishTrie(words: ["the", "they", "them", "there"])
    setToggle("shift")
    let (c, m) = newController()
    let t0 = ProcessInfo.processInfo.systemUptime
    _ = c.handleWithNewEngine(flagsEvent(56, [.shift], ts: t0), client: m)
    _ = c.handleWithNewEngine(flagsEvent(56, [], ts: t0 + 0.1), client: m)
    check(c.engine.isEnglishMode, "E14d0 進英文模式")
    _ = c.handleWithNewEngine(keyEvent(17), client: m)  // t
    _ = c.handleWithNewEngine(keyEvent(4), client: m)   // h
    _ = c.handleWithNewEngine(keyEvent(14), client: m)  // e
    check(m.marked == "the", "E14d1 字母累積為 marked 組字")
    _ = c.handleWithNewEngine(keyEvent(18), client: m)  // '1' → 第一候選 "they"
    check(m.inserted.last == "they", "E14d2 數字鍵選候選送出 they")
    check(m.marked.isEmpty, "E14d3 選字後 marked 清空")

    // 14e: Backspace 編輯 + Escape 丟棄
    _ = c.handleWithNewEngine(keyEvent(17), client: m)  // t
    _ = c.handleWithNewEngine(keyEvent(4), client: m)   // h
    _ = c.handleWithNewEngine(keyEvent(51), client: m)  // Backspace → "t"
    check(m.marked == "t", "E14e1 Backspace 刪組字")
    _ = c.handleWithNewEngine(keyEvent(53), client: m)  // Escape 丟棄
    check(m.marked.isEmpty && m.inserted.last != "t", "E14e2 Escape 丟棄不落底")

    // 14f: 大寫跟隨 — 全大寫前綴 → 大寫補全
    _ = c.handleWithNewEngine(keyEvent(17, [.shift]), client: m)  // T
    _ = c.handleWithNewEngine(keyEvent(4, [.shift]), client: m)   // H
    _ = c.handleWithNewEngine(keyEvent(14, [.shift]), client: m)  // E
    check(m.marked == "THE", "E14f1 全大寫前綴")
    _ = c.handleWithNewEngine(keyEvent(18), client: m)            // 選第一候選
    check(m.inserted.last == "THEY", "E14f2 全大寫→大寫補全 THEY")

    // 14g: 首字母大寫 → Capitalized
    _ = c.handleWithNewEngine(keyEvent(17, [.shift]), client: m)  // T
    _ = c.handleWithNewEngine(keyEvent(4), client: m)             // h
    _ = c.handleWithNewEngine(keyEvent(14), client: m)            // e
    _ = c.handleWithNewEngine(keyEvent(18), client: m)
    check(m.inserted.last == "They", "E14g 首大寫→They")

    // 14h: 空白放行先落前綴
    _ = c.handleWithNewEngine(keyEvent(17), client: m)  // t
    _ = c.handleWithNewEngine(keyEvent(4), client: m)   // h
    let consumed = c.handleWithNewEngine(keyEvent(49), client: m) // Space
    check(!consumed && m.inserted.last == "th", "E14h Space 先落前綴再放行")
    check(m.marked.isEmpty, "E14h2 放行後組字清")

    // 14i: 無匹配 ≥3 字母 → "+前綴" 虛候選；選它入字典
    _ = c.handleWithNewEngine(keyEvent(7), client: m)   // x
    _ = c.handleWithNewEngine(keyEvent(16), client: m)  // y
    _ = c.handleWithNewEngine(keyEvent(6), client: m)   // z
    check(m.marked == "xyz", "E14i1 無匹配前綴組字")
    _ = c.handleWithNewEngine(keyEvent(18), client: m)  // '1' → "+xyz"
    check(m.inserted.last == "xyz", "E14i2 選 +xyz 送出")
    // +word 寫進真實使用者字典（AppConstants.sharedDir）——測完清掉不污染
    UserEnglishDict(dir: AppConstants.sharedDir).remove("xyz")

    // 14j: 聯想關閉 → 英文模式字母直放（不組字）
    YabomishPrefs.englishSuggest = false
    let (c2, m2) = newController()
    c2.engine.setEnglishMode(true)
    _ = c2.handleWithNewEngine(keyEvent(17), client: m2)
    check(m2.marked.isEmpty && m2.inserted.last == "t", "E14j 關閉時字母直放")
    YabomishPrefs.englishSuggest = true
}

// ─── E15: 候選窗個性化渲染（與 HUD 共用 toast* 偏好）───
// 實體化 CandidatePanel 走公開 show API,由視圖層級檢驗字型/字色/描邊/背景層。
do {
    let panel = CandidatePanel.shared
    // 存還原值——e2e binary 沒 bundle id,suite 落到 stable,必須全部復原
    let d = YabomishPrefs.defaults
    let savedColorObj = d.object(forKey: "toastTextColor")
    let savedStyle = YabomishPrefs.toastFontStyle
    let savedStroke = YabomishPrefs.toastStroke
    let savedStrokeColor = YabomishPrefs.toastStrokeColor
    let savedHC = YabomishPrefs.highContrast
    let savedPos = YabomishPrefs.panelPosition
    let savedAlpha = YabomishPrefs.fixedAlpha
    let savedVE = YabomishPrefs.visualEffects

    func e15Labels() -> [NSTextField] {
        for v in panel.contentView?.subviews ?? [] {
            if let sv = v as? NSStackView {
                return sv.arrangedSubviews.compactMap { $0 as? NSTextField }
            }
        }
        return []
    }
    func e15Backdrop() -> NSView? { panel.contentView?.subviews.first }

    YabomishPrefs.panelPosition = "cursor"
    YabomishPrefs.highContrast = false
    YabomishPrefs.toastFontStyle = "serif"
    YabomishPrefs.toastStroke = false
    YabomishPrefs.toastTextColor = "#FF8800"

    panel.show(candidates: ["蝦", "米", "蟹"], selKeys: ["1", "2", "3"], at: NSPoint(x: 100, y: 500))
    var labs = e15Labels()
    check(labs.count >= 3, "E15a0 游標模式產出標籤列")
    if labs.count >= 3 {
        // 明體解析命中 Songti TC（一般列；labs[0] 為反白列）
        check((labs[1].font?.familyName ?? "").contains("Songti"), "E15a 明體→Songti TC 套用候選")
        // 自訂字色 #FF8800 套用一般列（無描邊時走 textColor）
        let g = labs[1].textColor?.usingColorSpace(.sRGB)?.greenComponent ?? -1
        check(abs(g - 0.533) < 0.02, "E15b 自訂字色套用一般列")
        // 反白列保留系統選取色，不吃自訂色
        check(labs[0].drawsBackground == true, "E15c1 反白列保留底色")
        let hg = labs[0].textColor?.usingColorSpace(.sRGB)?.greenComponent ?? -1
        check(abs(hg - 0.533) >= 0.02, "E15c2 反白列不吃自訂字色")
    }

    // 描邊開啟→屬性字串帶負 strokeWidth＋描邊色
    YabomishPrefs.toastStroke = true
    panel.show(candidates: ["蝦", "米", "蟹"], selKeys: ["1", "2", "3"], at: NSPoint(x: 100, y: 500))
    labs = e15Labels()
    if labs.count >= 3 {
        let attrs = labs[1].attributedStringValue.attributes(at: 0, effectiveRange: nil)
        let sw = (attrs[.strokeWidth] as? NSNumber)?.doubleValue ?? 0
        check(sw == -4.0 && attrs[.strokeColor] is NSColor, "E15d 描邊屬性（負 strokeWidth+描邊色）")
    }

    // 字色鍵未明確設定→走自適應 labelColor（不吃 HUD 白字預設）
    d.removeObject(forKey: "toastTextColor")
    YabomishPrefs.toastStroke = false
    panel.show(candidates: ["蝦", "米", "蟹"], selKeys: ["1", "2", "3"], at: NSPoint(x: 100, y: 500))
    labs = e15Labels()
    if labs.count >= 3 {
        let g = labs[1].textColor?.usingColorSpace(.sRGB)?.greenComponent ?? -1
        check(abs(g - 0.533) >= 0.02, "E15e 未設字色→自適應 labelColor")
    }
    if let saved = savedColorObj { d.set(saved, forKey: "toastTextColor") }

    // 固定模式：窗體不透明、fixedAlpha 只作用於背景層
    YabomishPrefs.panelPosition = "fixed"
    YabomishPrefs.fixedAlpha = 0.5
    panel.show(candidates: ["蝦", "米", "蟹"], selKeys: ["1", "2", "3"], at: NSPoint(x: 100, y: 500))
    let bgA = e15Backdrop()?.alphaValue ?? -1
    check(abs(bgA - 0.5) < 0.01, "E15f 固定窗 fixedAlpha 只淡背景層")

    // prefsChanged 即時刷新：不重 show 直接改視覺效果→背景層換型。
    // observer 註冊在 .main queue——post 後要泵 runloop 才會執行。
    func e15Pump() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1)) }
    YabomishPrefs.visualEffects = "none"
    DistributedNotificationCenter.default().postNotificationName(
        .init("com.yabomish.prefsChanged"), object: nil, userInfo: nil, deliverImmediately: true)
    e15Pump()
    check(e15Backdrop() is FlatBackdropView, "E15g prefsChanged 即時刷新→純色背景層")

    if #available(macOS 26.0, *) {
        YabomishPrefs.visualEffects = "full"
        DistributedNotificationCenter.default().postNotificationName(
            .init("com.yabomish.prefsChanged"), object: nil, userInfo: nil, deliverImmediately: true)
        e15Pump()
        check(e15Backdrop() is NSGlassEffectView, "E15h full→NSGlassEffectView 背景層")
    }

    panel.hide()
    YabomishPrefs.toastFontStyle = savedStyle
    YabomishPrefs.toastStroke = savedStroke
    YabomishPrefs.toastStrokeColor = savedStrokeColor
    YabomishPrefs.highContrast = savedHC
    YabomishPrefs.panelPosition = savedPos
    YabomishPrefs.fixedAlpha = savedAlpha
    YabomishPrefs.visualEffects = savedVE
}

print("\n=== \(passed) passed, \(failed) failed ===")
exit(failed == 0 ? 0 : 1)
