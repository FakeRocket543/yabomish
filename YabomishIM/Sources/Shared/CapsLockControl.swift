import IOKit

/// Caps Lock 硬體鎖定狀態控制（issue #18）。
///
/// 「⇪ 當中英切換鍵」模式下，caps press 的 flagsChanged 消費不掉系統
/// 已翻轉的鎖定狀態（事件派發前 latch/LED 已變）。開啟一次 IOHIDSystem
/// 連線，切換後用 IOHIDSetModifierLockState 把鎖定狀態恆壓回 off：
/// LED 不亮、.capsLock flag 不殘留，其他 app 不會收到漏出的大寫狀態。
/// 強制解除產生的合成 flagsChanged（flag=false）由呼叫端的 →ON 閘門濾掉。
enum CapsLockControl {

    private static let connection: io_connect_t = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        var conn: io_connect_t = 0
        if service != 0 {
            IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &conn)
            IOObjectRelease(service)
        }
        return conn
    }()

    /// IOHID 通道是否可用。不可用時呼叫端退回「每按壓切一次」
    /// （無 force-off 就不會有回聲事件，不需閘門）。
    static var available: Bool { connection != 0 }

    /// 讀目前 caps lock 鎖定狀態（讀不到回 false）。
    static func isLocked() -> Bool {
        var on = false
        guard connection != 0,
              IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &on) == KERN_SUCCESS
        else { return false }
        return on
    }

    /// 設定 caps lock 鎖定狀態（測試用；產品路徑只用 forceOff）。
    static func setLock(_ on: Bool) {
        guard connection != 0 else { return }
        IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), on)
    }

    /// 強制解除 caps lock 鎖定：LED 滅、.capsLock flag 清、其他 app 不受影響。
    static func forceOff() {
        setLock(false)
    }
}
