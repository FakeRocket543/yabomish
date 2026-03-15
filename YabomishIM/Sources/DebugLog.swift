import Foundation

/// Writes timestamped debug logs to ~/Library/YabomishIM/debug.log
enum DebugLog {
    private static let logPath = NSHomeDirectory() + "/Library/YabomishIM/debug.log"
    private static let maxSize = 512 * 1024  // 512 KB

    static func log(_ msg: String) {
        guard YabomishPrefs.debugMode else { return }
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(msg)\n"
        let fm = FileManager.default
        let dir = NSHomeDirectory() + "/Library/YabomishIM"
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: logPath) {
            fm.createFile(atPath: logPath, contents: nil)
        }
        // Rotate if too large
        if let attr = try? fm.attributesOfItem(atPath: logPath),
           let size = attr[.size] as? Int, size > maxSize {
            try? fm.removeItem(atPath: logPath + ".old")
            try? fm.moveItem(atPath: logPath, toPath: logPath + ".old")
            fm.createFile(atPath: logPath, contents: nil)
        }
        if let fh = FileHandle(forWritingAtPath: logPath) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8)!)
            fh.closeFile()
        }
    }
}
