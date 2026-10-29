import AppKit

func testModeSwitchGestures() {
    var gesture = InputModeSwitch()
    func event(_ code: UInt16, _ flags: NSEvent.ModifierFlags, _ time: TimeInterval,
               _ selection: String = "shift") -> Bool {
        gesture.flagsChanged(keyCode: code, flags: flags, timestamp: time, selection: selection)
    }

    check(!event(56, .shift, 1), "Shift down does not toggle")
    check(event(56, [], 1.1), "left Shift tap toggles")
    check(!event(60, .shift, 2), "right Shift down")
    check(event(60, [], 2.1), "right Shift tap toggles")
    _ = event(56, .shift, 3)
    check(!event(56, [], 3.5), "held Shift does not toggle")
    _ = event(56, .shift, 4)
    gesture.keyDown()
    check(!event(56, [], 4.1), "Shift typing does not toggle")

    _ = event(56, .shift, 5)
    _ = event(55, [.shift, .command], 5.02)
    gesture.keyDown()
    _ = event(55, .shift, 5.04)
    check(!event(56, [], 5.1), "Command-Shift shortcut does not toggle")
    _ = event(56, .shift, 6)
    _ = event(59, [.shift, .control], 6.02)
    _ = event(59, .shift, 6.04)
    check(!event(56, [], 6.1), "modifier chord without typing does not toggle")
    _ = event(56, .shift, 7)
    _ = event(57, [.shift, .capsLock], 7.02)
    check(!event(56, .capsLock, 7.1), "Caps Lock event cannot restart Shift tap")
    check(!event(57, [], 8), "Caps Lock disabled in Shift mode")

    check(event(57, .capsLock, 9, "capsLock"), "Caps Lock on toggles")
    check(!event(57, .capsLock, 9.1, "capsLock"), "duplicate latch state ignored")
    check(event(57, [], 10, "capsLock"), "Caps Lock off toggles")
    _ = event(56, .shift, 11, "capsLock")
    check(!event(56, [], 11.1, "capsLock"), "Shift tap disabled in Caps Lock mode")

    _ = event(56, .shift, 12)
    gesture.reset(flags: .capsLock)
    check(!event(56, .capsLock, 12.1), "activation cancels pending Shift tap")
    check(event(57, [], 13, "capsLock"), "activation while Caps Lock on tracks next off")
    _ = event(56, .shift, 14)
    _ = event(56, [], 14.1, "capsLock")
    check(!event(56, [], 14.2), "changing preference cancels pending tap")
}
