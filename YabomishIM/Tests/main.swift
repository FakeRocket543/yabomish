import Foundation

// Minimal test harness
var passed = 0
var failed = 0

func check(_ condition: Bool, _ msg: String = "", file: String = #file, line: Int = #line) {
    if condition { passed += 1 }
    else { failed += 1; print("FAIL [\(file):\(line)] \(msg)") }
}

func checkEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) {
    if a == b { passed += 1 }
    else { failed += 1; print("FAIL [\(file):\(line)] \(msg) — got \(a), expected \(b)") }
}

// === InputEngineDelegate protocol (copied for standalone compilation) ===
protocol InputEngineDelegate: AnyObject {
    func engineDidUpdateComposing(_ text: String)
    func engineDidUpdateCandidates(_ candidates: [String])
    func engineDidCommit(_ text: String)
    func engineDidCommitPair(_ left: String, _ right: String)
    func engineDidClearComposing()
    func engineDidShowToast(_ text: String)
    func engineDidDeleteBack()
    func engineDidSuggest(_ suggestions: [String])
}

// === Tests ===

func testHarness() {
    check(true, "true is true")
    check(!false, "not-false is true")
    checkEqual(1, 1, "1 == 1")
    checkEqual("abc", "abc", "string equality")
}

func testMockDelegateRecords() {
    let mock = MockEngineDelegate()
    mock.engineDidUpdateComposing("abc")
    mock.engineDidShowToast("A")
    mock.engineDidCommit("好")
    mock.engineDidCommitPair("左", "右")
    mock.engineDidClearComposing()
    mock.engineDidDeleteBack()
    mock.engineDidSuggest(["a", "b"])

    checkEqual(mock.composingUpdates.count, 1, "composing update recorded")
    checkEqual(mock.composingUpdates.first!, "abc", "composing value")
    checkEqual(mock.toasts.count, 1, "toast recorded")
    checkEqual(mock.toasts.first!, "A", "toast value")
    checkEqual(mock.commits.count, 1, "commit recorded")
    checkEqual(mock.commits.first!, "好", "commit value")
    checkEqual(mock.commitPairs.count, 1, "commitPair recorded")
    checkEqual(mock.clearCount, 1, "clear recorded")
    checkEqual(mock.deleteBackCount, 1, "deleteBack recorded")
    checkEqual(mock.suggestions.count, 1, "suggestions recorded")
    checkEqual(mock.suggestions.first!.count, 2, "suggestion items")
}

func testMockDelegateReset() {
    let mock = MockEngineDelegate()
    mock.engineDidCommit("x")
    mock.engineDidShowToast("t")
    mock.engineDidClearComposing()
    mock.engineDidDeleteBack()
    mock.reset()
    checkEqual(mock.commits.count, 0, "commits cleared after reset")
    checkEqual(mock.toasts.count, 0, "toasts cleared after reset")
    checkEqual(mock.clearCount, 0, "clearCount reset")
    checkEqual(mock.deleteBackCount, 0, "deleteBackCount reset")
}

func testMockDelegateMultipleCalls() {
    let mock = MockEngineDelegate()
    mock.engineDidUpdateComposing("a")
    mock.engineDidUpdateComposing("ab")
    mock.engineDidUpdateComposing("abc")
    checkEqual(mock.composingUpdates.count, 3, "three composing updates")
    checkEqual(mock.composingUpdates.last!, "abc", "last composing value")

    mock.engineDidUpdateCandidates(["好", "號"])
    mock.engineDidUpdateCandidates(["好"])
    checkEqual(mock.candidateUpdates.count, 2, "two candidate updates")
    checkEqual(mock.candidateUpdates.last!.count, 1, "last candidate count")
}

// Run all tests
print("Running YabomishIM tests...")
testHarness()
testMockDelegateRecords()
testMockDelegateReset()
testMockDelegateMultipleCalls()

print("\n\(passed) passed, \(failed) failed")
exit(failed > 0 ? 1 : 0)
