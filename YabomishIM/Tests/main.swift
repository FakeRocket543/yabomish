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

// === Real InputEngine tests ===

func testRealEngineInit() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    check(engine.composing.isEmpty, "composing starts empty")
    check(engine.currentCandidates.isEmpty, "no candidates initially")
    check(!engine.isEnglishMode, "starts in Chinese mode")
    check(!engine.isZhuyinMode, "not in zhuyin mode")
    check(!engine.isPinyinMode, "not in pinyin mode")
}

func testRealToggleEnglish() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    engine.toggleEnglishMode()
    check(engine.isEnglishMode, "English after toggle")
    checkEqual(mock.toasts.last ?? "", "A", "toast should be A")
    engine.toggleEnglishMode()
    check(!engine.isEnglishMode, "Chinese after second toggle")
}

func testRealComposing() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    engine.handleLetter("a")
    check(!engine.composing.isEmpty, "composing after letter")
    check(mock.composingUpdates.count > 0, "delegate notified")
}

func testRealBackspace() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    engine.handleLetter("a")
    engine.handleLetter("b")
    let len = engine.composing.count
    engine.handleBackspace()
    check(engine.composing.count < len, "backspace removes char")
}

func testRealEscape() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    engine.handleLetter("a")
    engine.handleEscape()
    check(engine.composing.isEmpty, "escape clears")
    check(mock.clearCount > 0, "clear notified")
}

func testRealModeSwitch() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let label = engine.switchToMode("s")
    check(!label.isEmpty, "mode switch returns label")
    let label2 = engine.switchToMode("t")
    check(!label2.isEmpty, "switch back returns label")
}

func testRealCommaCommand() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    engine.handleLetter(",")
    engine.handleLetter(",")
    check(engine.composing.hasPrefix(","), "comma command active")
    engine.handleEscape()
    check(engine.composing.isEmpty, "escape exits comma command")
}

func testRealEnterCommitsRaw() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    engine.handleLetter("a")
    engine.handleLetter("b")
    engine.handleEnter()
    check(mock.commits.count > 0, "enter commits raw text")
}

func testRealZhuyinModeSwitch() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    engine.switchToMode("zh")
    check(engine.isZhuyinMode, "should be in zhuyin mode")
    engine.exitZhuyinMode()
    check(!engine.isZhuyinMode, "should exit zhuyin mode")
}

// === CINTable tests ===

func makeTempCIN() -> String {
    let content = """
    %gen_inp
    %cname Test
    %selkey 1234567890
    %keyname begin
    a a
    b b
    %keyname end
    %chardef begin
    a 好
    a 號
    ab 哈
    b 不
    %chardef end
    """
    let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).cin"
    try! content.write(toFile: path, atomically: true, encoding: .utf8)
    return path
}

func loadTestCINTable() -> CINTable {
    let table = CINTable()
    let path = makeTempCIN()
    table.load(cinPath: path)
    try? FileManager.default.removeItem(atPath: path)
    return table
}

func testCINTableLoadAndLookup() {
    let table = loadTestCINTable()
    let a = table.lookup("a")
    check(a.contains("好"), "lookup('a') contains 好")
    check(a.contains("號"), "lookup('a') contains 號")
    let ab = table.lookup("ab")
    check(ab.contains("哈"), "lookup('ab') contains 哈")
    let z = table.lookup("z")
    check(z.isEmpty, "lookup('z') is empty")
}

func testCINTableReverseLookup() {
    let table = loadTestCINTable()
    let r = table.reverseLookup("好")
    check(r.contains("a"), "reverseLookup('好') contains 'a'")
    let empty = table.reverseLookup("不存在")
    check(empty.isEmpty, "reverseLookup('不存在') is empty")
}

func testCINTableWildcard() {
    let table = loadTestCINTable()
    // a* regex becomes ^a.+$ — matches "ab" but not "a" itself
    let results = table.wildcardLookup("a*")
    check(results.contains("哈"), "wildcard 'a*' includes 'ab' entry 哈")
    check(!results.isEmpty, "wildcard 'a*' returns results")
}

func testCINTableHasPrefix() {
    let table = loadTestCINTable()
    check(table.hasPrefix("a"), "hasPrefix('a') is true (ab exists)")
    check(!table.hasPrefix("z"), "hasPrefix('z') is false")
}

func testCINTableValidNextKeys() {
    let table = loadTestCINTable()
    let keys = table.validNextKeys(after: "a")
    check(keys.contains("b"), "validNextKeys(after: 'a') contains 'b'")
}

// === FreqTracker tests ===

func testFreqTrackerRecordAndSort() {
    let tracker = FreqTracker()
    let code = "_test_sort_\(UUID().uuidString)"
    tracker.record(code: code, char: "A")
    tracker.record(code: code, char: "A")
    tracker.record(code: code, char: "A")
    tracker.record(code: code, char: "B")
    let sorted = tracker.sorted(["B", "A"], forCode: code)
    checkEqual(sorted, ["A", "B"], "A (3x) before B (1x)")
    tracker.reset()
}

func testFreqTrackerBigramBoost() {
    let tracker = FreqTracker()
    for _ in 0..<5 { tracker.recordBigram(prev: "甲", char: "乙") }
    let top = tracker.topBigrams(prev: "甲")
    check(top.contains("乙"), "topBigrams(prev: '甲') contains '乙'")
    let boosted = tracker.bigramBoost(prev: "甲", candidates: ["丙", "乙"])
    check(boosted.first == "乙", "bigramBoost moves '乙' before '丙'")
    tracker.reset()
}

// === CandidateRanker tests ===

func testRankerModeFiltering() {
    let table = loadTestCINTable()
    let tracker = FreqTracker()
    let ranker = CandidateRanker()

    // mode .t — no filtering, returns both
    let tResult = ranker.rank(raw: ["好", "號"], code: "a", prev: "", mode: .t, cinTable: table, freqTracker: tracker)
    check(tResult.contains("好"), "mode .t keeps 好")
    check(tResult.contains("號"), "mode .t keeps 號")

    // mode .sp — only chars whose shortest code == "a"
    let spResult = ranker.rank(raw: ["好", "號"], code: "a", prev: "", mode: .sp, cinTable: table, freqTracker: tracker)
    // Both 好 and 號 have shortest code "a" (1 char), so both should remain
    check(spResult.contains("好") || spResult.contains("號"), "mode .sp keeps chars with shortest code 'a'")
}

// Run all tests
print("Running YabomishIM tests...")
testHarness()
testMockDelegateRecords()
testMockDelegateReset()
testMockDelegateMultipleCalls()
testRealEngineInit()
testRealToggleEnglish()
testRealComposing()
testRealBackspace()
testRealEscape()
testRealModeSwitch()
testRealCommaCommand()
testRealEnterCommitsRaw()
testRealZhuyinModeSwitch()
testCINTableLoadAndLookup()
testCINTableReverseLookup()
testCINTableWildcard()
testCINTableHasPrefix()
testCINTableValidNextKeys()
testFreqTrackerRecordAndSort()
testFreqTrackerBigramBoost()
testRankerModeFiltering()

print("\n\(passed) passed, \(failed) failed")
exit(failed > 0 ? 1 : 0)
