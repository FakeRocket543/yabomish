import Foundation

// MARK: - API gap stubs (macOS missing methods)

extension FreqTracker {
    func deferredMerge() { /* no-op on macOS for now */ }
    func recordTrigram(prev2: String, prev1: String, char: String) { /* no-op stub */ }
}

