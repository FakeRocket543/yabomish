import Foundation

class MockEngineDelegate: InputEngineDelegate {
    var composingUpdates: [String] = []
    var candidateUpdates: [[String]] = []
    var commits: [String] = []
    var commitPairs: [(String, String)] = []
    var clearCount = 0
    var toasts: [String] = []
    var deleteBackCount = 0
    var suggestions: [[String]] = []

    func engineDidUpdateComposing(_ text: String) { composingUpdates.append(text) }
    func engineDidUpdateCandidates(_ candidates: [String]) { candidateUpdates.append(candidates) }
    func engineDidCommit(_ text: String) { commits.append(text) }
    func engineDidCommitPair(_ left: String, _ right: String) { commitPairs.append((left, right)) }
    func engineDidClearComposing() { clearCount += 1 }
    func engineDidShowToast(_ text: String) { toasts.append(text) }
    func engineDidDeleteBack() { deleteBackCount += 1 }
    func engineDidSuggest(_ suggestions: [String]) { self.suggestions.append(suggestions) }

    func reset() {
        composingUpdates = []; candidateUpdates = []; commits = []
        commitPairs = []; clearCount = 0; toasts = []; deleteBackCount = 0; suggestions = []
    }
}
