import Foundation

/// Zhuyin syllable composer: tracks initial/medial/final slots and builds the buffer.
/// Pure state machine — extracted from InputEngine (god-class surgery, zero behavior change).
struct ZhuyinComposer {
    private(set) var initial = ""
    private(set) var medial = ""
    private(set) var final_ = ""

    private static let initials: Set<String> = [
        "ㄅ","ㄆ","ㄇ","ㄈ","ㄉ","ㄊ","ㄋ","ㄌ",
        "ㄍ","ㄎ","ㄏ","ㄐ","ㄑ","ㄒ","ㄓ","ㄔ","ㄕ","ㄖ","ㄗ","ㄘ","ㄙ",
    ]
    private static let medials: Set<String> = ["ㄧ","ㄨ","ㄩ"]
    private static let finals: Set<String> = [
        "ㄚ","ㄛ","ㄜ","ㄝ","ㄞ","ㄟ","ㄠ","ㄡ","ㄢ","ㄣ","ㄤ","ㄥ","ㄦ",
    ]

    var buffer: String { initial + medial + final_ }
    var isEmpty: Bool { buffer.isEmpty }

    /// Slot a symbol into initial/medial/final. Unknown symbols are ignored.
    /// Returns true when the composer changed.
    @discardableResult
    mutating func input(_ zy: String) -> Bool {
        if Self.initials.contains(zy) { initial = zy }
        else if Self.medials.contains(zy) { medial = zy }
        else if Self.finals.contains(zy) { final_ = zy }
        else { return false }
        return true
    }

    /// Backspace pops final → medial → initial (same order the engine used).
    mutating func backspace() {
        if !final_.isEmpty { final_ = "" }
        else if !medial.isEmpty { medial = "" }
        else { initial = "" }
    }

    mutating func clear() { initial = ""; medial = ""; final_ = "" }
}
