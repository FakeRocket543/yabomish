import AppKit

/// Tracks modifier gestures independently of the client and engine.
struct InputModeSwitch {
    private var shiftDownAt: TimeInterval?
    private var shiftUsed = false
    private var capsLock = false

    mutating func reset(flags: NSEvent.ModifierFlags) {
        shiftDownAt = nil
        shiftUsed = false
        capsLock = flags.contains(.capsLock)
    }

    mutating func keyDown() {
        if shiftDownAt != nil { shiftUsed = true }
    }

    mutating func flagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags,
                               timestamp: TimeInterval, selection: String) -> Bool {
        let caps = flags.contains(.capsLock)
        let capsChanged = caps != capsLock
        capsLock = caps

        if selection == "capsLock" {
            shiftDownAt = nil
            return keyCode == 57 && capsChanged
        }

        let otherModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .function]
        guard flags.intersection(otherModifiers).isEmpty else {
            shiftDownAt = nil
            return false
        }
        // Other modifier events must not restart a Shift gesture.
        guard keyCode == 56 || keyCode == 60 else {
            if shiftDownAt != nil { shiftUsed = true }
            return false
        }
        if flags.contains(.shift) {
            if shiftDownAt == nil {
                shiftDownAt = timestamp
                shiftUsed = false
            }
            return false
        }
        defer { shiftDownAt = nil }
        guard let down = shiftDownAt else { return false }
        return timestamp - down >= 0 && timestamp - down < 0.3 && !shiftUsed
    }
}
