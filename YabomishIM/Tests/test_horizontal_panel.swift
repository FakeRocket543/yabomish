import Cocoa

// E2E test: CandidatePanel horizontal cursor mode
// This test includes CandidatePanel and verifies layout toggling.

var passed = 0
var failed = 0

func check(_ condition: Bool, _ msg: String = "", file: String = #file, line: Int = #line) {
    if condition { passed += 1 }
    else { failed += 1; print("FAIL [\(file):\(line)] \(msg)") }
}

func checkEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) {
    if a == b { passed += 1 }
    else { failed += 1; print("FAIL [\(file):\(line)] \(a) != \(b) — \(msg)") }
}

// --- Tests ---

func testPrefDefaultFalse() {
    // Reset to ensure clean state
    UserDefaults.standard.removeObject(forKey: "cursorHorizontal")
    checkEqual(YabomishPrefs.cursorHorizontal, false, "default is vertical (false)")
}

func testPrefToggle() {
    YabomishPrefs.cursorHorizontal = true
    checkEqual(YabomishPrefs.cursorHorizontal, true, "set to horizontal")
    YabomishPrefs.cursorHorizontal = false
    checkEqual(YabomishPrefs.cursorHorizontal, false, "set back to vertical")
}

func testPanelVerticalLayout() {
    UserDefaults.standard.removeObject(forKey: "cursorHorizontal")
    UserDefaults.standard.set("cursor", forKey: "panelPosition")

    let panel = CandidatePanel.shared
    let cands = ["好", "號", "毫", "豪", "壕"]
    let selKeys: [Character] = ["1", "2", "3", "4", "5"]

    panel.show(candidates: cands, selKeys: selKeys, at: NSPoint(x: 200, y: 400))

    // Give main runloop a tick to process onMain block
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

    check(panel.isVisible_, "panel should be visible")
    // In vertical mode, panel should be taller than wide (for short candidates)
    let frame = panel.frame
    check(frame.height > frame.width * 0.5, "vertical: height should be significant relative to width (\(frame.width)x\(frame.height))")
    panel.hide()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
}

func testPanelHorizontalLayout() {
    YabomishPrefs.cursorHorizontal = true
    UserDefaults.standard.set("cursor", forKey: "panelPosition")

    let panel = CandidatePanel.shared
    let cands = ["好", "號", "毫", "豪", "壕"]
    let selKeys: [Character] = ["1", "2", "3", "4", "5"]

    panel.show(candidates: cands, selKeys: selKeys, at: NSPoint(x: 200, y: 400))
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

    check(panel.isVisible_, "panel should be visible (horizontal)")
    let frame = panel.frame
    // In horizontal mode, panel should be wider than tall
    check(frame.width > frame.height, "horizontal: width (\(frame.width)) > height (\(frame.height))")
    panel.hide()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

    // Cleanup
    YabomishPrefs.cursorHorizontal = false
}

func testPanelNavigationHorizontal() {
    YabomishPrefs.cursorHorizontal = true
    UserDefaults.standard.set("cursor", forKey: "panelPosition")

    let panel = CandidatePanel.shared
    let cands = ["好", "號", "毫"]
    let selKeys: [Character] = ["1", "2", "3"]

    panel.show(candidates: cands, selKeys: selKeys, at: NSPoint(x: 200, y: 400))
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

    // Initial selection should be first
    checkEqual(panel.selectedCandidate(), "好", "initial selection")

    panel.moveNext()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    checkEqual(panel.selectedCandidate(), "號", "moveNext → second")

    panel.moveNext()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    checkEqual(panel.selectedCandidate(), "毫", "moveNext → third")

    panel.movePrev()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    checkEqual(panel.selectedCandidate(), "號", "movePrev → back to second")

    panel.hide()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    YabomishPrefs.cursorHorizontal = false
}

func testPanelSelectByKey() {
    YabomishPrefs.cursorHorizontal = true
    UserDefaults.standard.set("cursor", forKey: "panelPosition")

    let panel = CandidatePanel.shared
    let cands = ["蝦", "米", "蟹"]
    let selKeys: [Character] = ["1", "2", "3"]

    panel.show(candidates: cands, selKeys: selKeys, at: NSPoint(x: 200, y: 400))
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

    checkEqual(panel.selectByKey("1"), "蝦", "key 1 selects first")
    checkEqual(panel.selectByKey("2"), "米", "key 2 selects second")
    checkEqual(panel.selectByKey("3"), "蟹", "key 3 selects third")
    check(panel.selectByKey("9") == nil, "key 9 out of range returns nil")

    panel.hide()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    YabomishPrefs.cursorHorizontal = false
}

func testPanelPaging() {
    YabomishPrefs.cursorHorizontal = true
    UserDefaults.standard.set("cursor", forKey: "panelPosition")

    let panel = CandidatePanel.shared
    // More than 9 candidates to trigger paging
    let cands = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "百"]
    let selKeys: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    panel.show(candidates: cands, selKeys: selKeys, at: NSPoint(x: 200, y: 400))
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

    checkEqual(panel.selectedCandidate(), "一", "page 1 first item")

    panel.pageDown()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    checkEqual(panel.selectedCandidate(), "十", "page 2 first item")

    panel.pageUp()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    checkEqual(panel.selectedCandidate(), "一", "back to page 1")

    panel.hide()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    YabomishPrefs.cursorHorizontal = false
}

// --- Suggestion preselect (聯想預先反白開關) ---

func testPreselectPrefToggle() {
    // 預設值（false）由 Snapshot 建立時決定，無法在單一 process 內重載驗證；
    // 此處驗證 setter／getter round-trip
    YabomishPrefs.suggestPreselect = false
    checkEqual(YabomishPrefs.suggestPreselect, false, "set to false")
    YabomishPrefs.suggestPreselect = true
    checkEqual(YabomishPrefs.suggestPreselect, true, "set back to true")
    YabomishPrefs.suggestPreselect = false
    checkEqual(YabomishPrefs.suggestPreselect, false, "restore default (off)")
}

func testPanelShowDefaultsToPreselect() {
    // panel API 層預設反白（組字候選安全）；偏好層預設關，由 controller 傳參決定
    UserDefaults.standard.set("cursor", forKey: "panelPosition")

    let panel = CandidatePanel.shared
    let cands = ["好", "號", "毫"]
    let selKeys: [Character] = ["1", "2", "3"]

    panel.show(candidates: cands, selKeys: selKeys, at: NSPoint(x: 200, y: 400))
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

    checkEqual(panel.selectedCandidate(), "好", "default show preselects first candidate")

    panel.hide()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
}

func testPreselectOffNoHighlight() {
    UserDefaults.standard.set("cursor", forKey: "panelPosition")

    let panel = CandidatePanel.shared
    let cands = ["好", "號", "毫"]
    let selKeys: [Character] = ["1", "2", "3"]

    panel.show(candidates: cands, selKeys: selKeys, at: NSPoint(x: 200, y: 400), preselectFirst: false)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

    check(panel.selectedCandidate() == nil, "preselect off: no highlighted candidate")
    checkEqual(panel.selectByKey("2"), "號", "preselect off: number key still selects")

    // 方向鍵從未反白狀態進入列表：落在第一個候選
    panel.moveNext()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    checkEqual(panel.selectedCandidate(), "好", "moveNext from none → first")

    panel.moveNext()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    checkEqual(panel.selectedCandidate(), "號", "moveNext → second")

    panel.movePrev()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    checkEqual(panel.selectedCandidate(), "好", "movePrev → back to first")

    panel.movePrev()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    checkEqual(panel.selectedCandidate(), "好", "movePrev at first stays")

    // moveUp 對未反白狀態同樣落在第一個候選
    panel.hide()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    panel.show(candidates: cands, selKeys: selKeys, at: NSPoint(x: 200, y: 400), preselectFirst: false)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    panel.moveUp()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    checkEqual(panel.selectedCandidate(), "好", "moveUp from none → first")

    panel.hide()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
}

// --- Run ---

@main
struct TestRunner {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        testPrefDefaultFalse()
        testPrefToggle()
        testPreselectPrefToggle()
        testPanelVerticalLayout()
        testPanelHorizontalLayout()
        testPanelNavigationHorizontal()
        testPanelSelectByKey()
        testPanelPaging()
        testPanelShowDefaultsToPreselect()
        testPreselectOffNoHighlight()

        print("\n\(passed) passed, \(failed) failed")
        exit(failed > 0 ? 1 : 0)
    }
}
