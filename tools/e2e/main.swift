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
        if let s = string as? String { inserted.append(s) }
        else if let s = string as? NSAttributedString { inserted.append(s.string) }
    }
    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        marked = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
    }
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
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
}

// ─── E7: pref=none — 兩鍵皆不切、.capsLock 恢復大寫語意 ───
do {
    setToggle("none")
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

print("\n=== \(passed) passed, \(failed) failed ===")
exit(failed == 0 ? 0 : 1)
