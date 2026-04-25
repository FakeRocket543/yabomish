import Foundation

enum AppConstants {
    #if os(iOS)
    static let appGroupID = "group.com.yabomishim.keyboard"
    static let bundleIDApp = "com.yabomishim.app"
    static let bundleIDKeyboard = "com.yabomishim.app.keyboard"

    static var sharedDir: String {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?.path
            ?? NSHomeDirectory() + "/Documents"
    }
    #else
    static var sharedDir: String {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return NSHomeDirectory() + "/Library/Application Support/Yabomish"
        }
        let dir = appSupport.appendingPathComponent("Yabomish")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }
    #endif

    static var cinPath: String {
        let primary = sharedDir + "/liu.cin"
        if FileManager.default.fileExists(atPath: primary) { return primary }
        // Legacy fallback: ~/Library/YabomishIM/liu.cin
        let legacy = NSHomeDirectory() + "/Library/YabomishIM/liu.cin"
        if FileManager.default.fileExists(atPath: legacy) { return legacy }
        return primary
    }
    static var freqPath: String { sharedDir + "/freq.db" }
    static var tablesDir: String { sharedDir + "/tables" }
}
