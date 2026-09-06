import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ClipboardProcessor {

    /// Read plain text from clipboard (strips all formatting)
    static func plainText() -> String? {
        #if os(macOS)
        NSPasteboard.general.string(forType: .string)
        #else
        UIPasteboard.general.string
        #endif
    }

    /// Simplified → Traditional Chinese
    static func toTraditional(_ text: String) -> String {
        text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
    }

    /// Traditional → Simplified Chinese
    static func toSimplified(_ text: String) -> String {
        text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
    }
}
