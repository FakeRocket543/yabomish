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

func testCommaCommandTextExpand() {
    // commands.json v2 契約：type:text 跨平台展開
    let tmp = NSTemporaryDirectory() + "/cmd-test-\(UUID().uuidString).json"
    let json = """
    {"auau": {"type": "text", "text": "sudo apt update && sudo apt upgrade"},
     "ss":   {"type": "shell", "run": "echo hi"}}
    """
    try? json.write(toFile: tmp, atomically: true, encoding: .utf8)
    CommaCommandRunner.reload(path: tmp)
    defer { CommaCommandRunner.reload(); try? FileManager.default.removeItem(atPath: tmp) }

    checkEqual(CommaCommandRunner.expandText("auau"), "sudo apt update && sudo apt upgrade", "expandText returns text payload")
    checkEqual(CommaCommandRunner.expandText("ss"), nil, "shell command is not text-expandable")
    checkEqual(CommaCommandRunner.expandText("nope"), nil, "unknown command returns nil")

    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    CommaCommandRunner.reload(path: tmp) // after engine init (init reloads real config)
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    for c in [",", ",", "a", "u", "a", "u"] { engine.handleLetter(c) }
    engine.handleSpace()
    checkEqual(mock.commits.first, "sudo apt update && sudo apt upgrade", ",,auau commits expanded text")
    check(engine.composing.isEmpty, "composing cleared after text expand")
}

func testHermesReplyParsing() {
    checkEqual(CommaCommandRunner._hermesReplyText(#"{"text":"回覆一"}"#), "回覆一", "JSON text key")
    checkEqual(CommaCommandRunner._hermesReplyText(#"{"reply":"回覆二"}"#), "回覆二", "JSON reply key")
    checkEqual(CommaCommandRunner._hermesReplyText(#"{"response":"回覆三"}"#), "回覆三", "JSON response key")
    checkEqual(CommaCommandRunner._hermesReplyText(#"{"content":"回覆四"}"#), "回覆四", "JSON content key")
    checkEqual(CommaCommandRunner._hermesReplyText("純文字回覆"), "純文字回覆", "plain text passthrough")
    checkEqual(CommaCommandRunner._hermesReplyText(#"{"other":"x"}"#), #"{"other":"x"}"#, "unknown JSON falls back to raw body")
    checkEqual(CommaCommandRunner._hermesReplyText(#"{"text":""}"#), #"{"text":""}"#, "empty text falls back to raw body")
}


func testHermesEndpointLoopbackOnly() {
    checkEqual(CommaCommandRunner.hermesEndpoint(nil)?.absoluteString, "http://127.0.0.1:8765/ask", "nil → default loopback")
    checkEqual(CommaCommandRunner.hermesEndpoint("http://127.0.0.1:9000/ask")?.absoluteString, "http://127.0.0.1:9000/ask", "127.0.0.1 allowed")
    checkEqual(CommaCommandRunner.hermesEndpoint("http://localhost:9000/x")?.absoluteString, "http://localhost:9000/x", "localhost allowed")
    check(CommaCommandRunner.hermesEndpoint("http://[::1]:8765/ask") != nil, "ipv6 loopback allowed")
    check(CommaCommandRunner.hermesEndpoint("http://evil.example.com/ask") == nil, "domain rejected")
    check(CommaCommandRunner.hermesEndpoint("http://192.168.1.5/ask") == nil, "LAN IP rejected")
    check(CommaCommandRunner.hermesEndpoint("https://127.0.0.1/ask") == nil, "https rejected")
    check(CommaCommandRunner.hermesEndpoint("ftp://127.0.0.1/ask") == nil, "non-http scheme rejected")
    check(CommaCommandRunner.hermesEndpoint("not a url") == nil, "garbage rejected")
}
func testCommaCommandHermesDecode() {
    let tmp = NSTemporaryDirectory() + "/cmd-hermes-\(UUID().uuidString).json"
    let json = """
    {"ask": {"type": "hermes", "send": "幫我總結", "url": "http://127.0.0.1:9991/ask"}}
    """
    try? json.write(toFile: tmp, atomically: true, encoding: .utf8)
    CommaCommandRunner.reload(path: tmp)
    defer { CommaCommandRunner.reload(); try? FileManager.default.removeItem(atPath: tmp) }

    checkEqual(CommaCommandRunner.expandText("ask"), nil, "hermes command is not text-expandable")
    // hermes matched by tryExecute (fires async request; no listener here → error toast path)
    var toastSeen = ""
    let matched = CommaCommandRunner.tryExecute("ask", toast: { toastSeen = $0 }) { _ in }
    check(matched, "hermes command matched by tryExecute")
    check(!CommaCommandRunner.tryExecute("nope", toast: { _ in }) { _ in }, "unknown command unmatched")
    // give async request a moment to fail (connection refused) — toast must fire, no crash
    let deadline = Date().addingTimeInterval(1.0)
    while Date() < deadline && toastSeen.isEmpty { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
    check(toastSeen.contains("Hermes"), "refused connection surfaces error toast, got: \(toastSeen)")
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
    tracker.flushAll()
    let sorted = tracker.sorted(["B", "A"], forCode: code)
    checkEqual(sorted, ["A", "B"], "A (3x) before B (1x)")
    tracker.reset()
}

func testFreqTrackerBigramBoost() {
    let tracker = FreqTracker()
    for _ in 0..<5 { tracker.recordBigram(prev: "甲", char: "乙") }
    tracker.flushAll()
    let top = tracker.topBigrams(prev: "甲")
    check(top.contains("乙"), "topBigrams(prev: '甲') contains '乙'")
    let boosted = tracker.bigramBoost(prev: "甲", candidates: ["丙", "乙"])
    check(boosted.first == "乙", "bigramBoost moves '乙' before '丙'")
    tracker.reset()
}

func testFreqTrackerImmediateCacheSort() {
    let tracker = FreqTracker()
    let code = "_test_cache_\(UUID().uuidString)"
    tracker.record(code: code, char: "甲")
    tracker.record(code: code, char: "甲")
    tracker.record(code: code, char: "乙")
    // No flushAll: in-memory cache must reflect recordings immediately
    let sorted = tracker.sorted(["乙", "甲"], forCode: code)
    checkEqual(sorted, ["甲", "乙"], "cache sort visible without flush")
    tracker.reset()
}

func testFreqTrackerResetNoResurrect() {
    let tracker = FreqTracker()
    let code = "_test_reset_\(UUID().uuidString)"
    for _ in 0..<10 { tracker.record(code: code, char: "丙") } // < batchSize, stays pending
    tracker.reset()
    tracker.flushAll()
    let sorted = tracker.sorted(["丁", "丙"], forCode: code)
    checkEqual(sorted, ["丁", "丙"], "reset clears pending — no resurrection after flush")
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

// === Integration tests: full typing flow ===

func testIntegrationTypeAndCommit() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    // Load a test CIN table
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    // Type "a" → should have candidates 好/號
    engine.handleLetter("a")
    checkEqual(engine.composing, "a", "composing is 'a'")
    check(engine.currentCandidates.count >= 2, "candidates for 'a'")

    // Space on extendable single code → commit first candidate directly (guard removed)
    engine.handleSpace()
    checkEqual(mock.commits.count, 1, "space on single code commits directly")
    let committed = mock.commits.first ?? ""
    check(committed == "好" || committed == "號", "committed a valid char")
    check(engine.composing.isEmpty, "composing cleared after commit")
    check(mock.toasts.isEmpty, "no hint toast on single-code space")
}

func testIntegrationTypeMultiChar() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    // Type "ab" → should have candidate 哈
    engine.handleLetter("a")
    engine.handleLetter("b")
    checkEqual(engine.composing, "ab", "composing is 'ab'")
    check(engine.currentCandidates.contains("哈"), "candidates contain 哈")

    // Space → commit
    engine.handleSpace()
    checkEqual(mock.commits.first, "哈", "committed 哈")
}

func testIntegrationBackspaceAndRetype() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    engine.handleLetter("a")
    engine.handleLetter("b")
    engine.handleBackspace()
    checkEqual(engine.composing, "a", "backspace removes last char")
    engine.handleLetter("b")
    checkEqual(engine.composing, "ab", "retype after backspace")
    engine.handleSpace()
    checkEqual(mock.commits.first, "哈", "commit after backspace+retype")
}

func testSingleCodeSpaceDirectCommit() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    // 'a' is single-char and extendable (ab exists) → space commits directly, no guard
    engine.handleLetter("a")
    engine.handleSpace()
    checkEqual(mock.commits.count, 1, "first space on extendable single code commits")
    check(engine.composing.isEmpty, "composing cleared after commit")
    check(mock.toasts.isEmpty, "no hint toast")
    // Extending to a two-char code still commits on first space
    engine.handleLetter("a")
    engine.handleLetter("b")
    engine.handleSpace()
    checkEqual(mock.commits.count, 2, "two-char code commits on first space")
}

func testIntegrationEscapeCancels() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    engine.handleLetter("a")
    engine.handleEscape()
    check(engine.composing.isEmpty, "escape clears composing")
    check(engine.currentCandidates.isEmpty, "escape clears candidates")
    checkEqual(mock.commits.count, 0, "escape does not commit")
}

func testIntegrationEnterCommitsRawCode() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    engine.handleLetter("a")
    engine.handleLetter("b")
    engine.handleEnter()
    check(mock.commits.contains("ab"), "enter commits raw code 'ab'")
}

func testIntegrationDigitSelect() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    engine.handleLetter("a")
    // "a" has 好 and 號 — select second with digit 2
    if engine.currentCandidates.count >= 2 {
        let second = engine.currentCandidates[1]
        engine.selectCandidate(at: 1)
        check(mock.commits.contains(second), "digit 2 selects second candidate")
    }
}

func testIntegrationCommaCommandMode() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock

    // ,,S → switch to simplified Chinese
    engine.handleLetter(",")
    engine.handleLetter(",")
    engine.handleLetter("s")
    engine.handleSpace()
    check(mock.toasts.count > 0, "comma command shows toast")
}

func testIntegrationQuotePassthrough() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock

    // ' key is no longer intercepted — no engine method to call
    // Just verify engine doesn't have any quote-related side effects
    check(engine.composing.isEmpty, "composing stays empty without quote handler")
    checkEqual(mock.commits.count, 0, "no commits without input")
}

func testIntegrationSequentialCommits() {
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    // Type and commit multiple chars in sequence
    // (single extendable codes now need two spaces — first shows hint)
    engine.handleLetter("a")
    engine.handleSpace()
    engine.handleSpace()
    engine.handleLetter("b")
    engine.handleSpace()
    engine.handleSpace()
    engine.handleLetter("a")
    engine.handleLetter("b")
    engine.handleSpace()

    check(mock.commits.count == 3, "three sequential commits")
}

func testSnippetOverflowCommitsExpansion() {
    // 回歸：auau 候選為 snippet 顯示字串時，滿碼後續打（overflow）必須送出展開文字，
    // 不是截斷顯示字串（曾 commit "📝 sudo apt update && sudo apt u..."）
    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    let realCommands = AppConstants.sharedDir + "/commands.json"
    guard FileManager.default.contents(atPath: realCommands) != nil,
          UserSnippets.shared.expansion(for: "auau") != nil else {
        print("SKIP testSnippetOverflowCommitsExpansion (live commands.json 無 auau)")
        return
    }

    for c in ["a", "u", "a", "u"] { engine.handleLetter(c) }
    engine.handleLetter("x") // 溢出 maxCodeLength → 觸發第一候選 commit
    let joined = mock.commits.joined()
    check(joined.contains("sudo apt update"), "overflow commits snippet expansion")
    check(!joined.contains("📝"), "overflow never commits display string")
    checkEqual(engine.composing, "x", "overflow char starts new composing")
}

func testSnippetAutoCommitSendsExpansion() {
    // 回歸：autoCommit 開啟時，唯一候選為 snippet 也要送展開文字
    let prev = YabomishPrefs.autoCommit
    YabomishPrefs.autoCommit = true
    defer { YabomishPrefs.autoCommit = prev }

    let engine = InputEngine()
    let mock = MockEngineDelegate()
    engine.delegate = mock
    let cinPath = makeTempCIN()
    engine.cinTable.load(cinPath: cinPath)
    try? FileManager.default.removeItem(atPath: cinPath)

    guard UserSnippets.shared.expansion(for: "auau") != nil else {
        print("SKIP testSnippetAutoCommitSendsExpansion (live commands.json 無 auau)")
        return
    }

    for c in ["a", "u", "a", "u"] { engine.handleLetter(c) }
    let joined = mock.commits.joined()
    check(joined.contains("sudo apt update"), "autoCommit sends snippet expansion")
    check(!joined.contains("📝"), "autoCommit never commits display string")
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
testCommaCommandTextExpand()
testHermesEndpointLoopbackOnly()
testHermesReplyParsing()
testCommaCommandHermesDecode()
testRealEnterCommitsRaw()
testRealZhuyinModeSwitch()
testCINTableLoadAndLookup()
testCINTableReverseLookup()
testCINTableWildcard()
testCINTableHasPrefix()
testCINTableValidNextKeys()
testFreqTrackerRecordAndSort()
testFreqTrackerBigramBoost()
testFreqTrackerImmediateCacheSort()
testFreqTrackerResetNoResurrect()
testRankerModeFiltering()
testIntegrationTypeAndCommit()
testIntegrationTypeMultiChar()
testIntegrationBackspaceAndRetype()
testSingleCodeSpaceDirectCommit()
testIntegrationEscapeCancels()
testIntegrationEnterCommitsRawCode()
testIntegrationDigitSelect()
testIntegrationCommaCommandMode()
testIntegrationQuotePassthrough()
testIntegrationSequentialCommits()

testSnippetOverflowCommitsExpansion()
testSnippetAutoCommitSendsExpansion()
print("\n\(passed) passed, \(failed) failed")
exit(failed > 0 ? 1 : 0)
