import Foundation

/// Writes timestamped debug logs to AppConstants.sharedDir/debug.log
enum DebugLog {
    private static var logPath: String { AppConstants.sharedDir + "/debug.log" }
    private static let maxSize = 512 * 1024  // 512 KB

    static func log(_ msg: String) {
        guard YabomishPrefs.debugMode else { return }
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(msg)\n"
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
