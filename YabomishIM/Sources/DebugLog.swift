import Foundation

/// Writes timestamped debug logs to AppConstants.sharedDir/debug.log
enum DebugLog {
    private static var logPath: String { AppConstants.sharedDir + "/debug.log" }
    private static let formatter = ISO8601DateFormatter()
    private static let maxSize = 512 * 1024  // 512 KB
    /// 保護檔案寫入（建立／輪替／附加）的鎖：多執行緒同時寫 log 時避免內容交錯。
    private static let writeLock = NSLock()

    /// 以 @autoclosure 延遲組字：debugMode 關閉時（常態）訊息字串完全不求值，
    /// 呼叫端即使傳入昂貴的插值運算也不付出成本。
    static func log(_ message: @autoclosure () -> String) {
        guard YabomishPrefs.debugMode else { return }
        writeLock.lock()
        defer { writeLock.unlock() }
        let ts = formatter.string(from: Date())
        let line = "[\(ts)] \(message())\n"
        let fm = FileManager.default
        let dir = AppConstants.sharedDir
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = logPath
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        // Rotate if too large
        if let attr = try? fm.attributesOfItem(atPath: path),
           let size = attr[.size] as? Int, size > maxSize {
            try? fm.removeItem(atPath: path + ".old")
            try? fm.moveItem(atPath: path, toPath: path + ".old")
            fm.createFile(atPath: path, contents: nil)
        }
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8)!)
            fh.closeFile()
        }
    }
}
