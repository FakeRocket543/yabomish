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
        // 依 bundle ID 尾碼取目錄：stable=Yabomish、dev 變體（YabomishDev）各自獨立，
        // 實驗不會弄髒正式版字頻/語料。不用 CFBundleName：build script 會把它設成
        // app 名（YabomishIM / YabomishDev），顯示名不該決定資料目錄。
        let bid = Bundle.main.bundleIdentifier ?? ""
        var comp = bid.components(separatedBy: ".").last ?? ""
        // app 名與資料名之間只差 "IM"：YabomishIM→Yabomish、
        // YabomishIMDev→YabomishDev、YabomishIME2E→YabomishE2E（YABOMISH_BID 變體沿用）
        if comp.hasPrefix("YabomishIM") { comp = "Yabomish" + comp.dropFirst("YabomishIM".count) }
        let dirName = comp.hasPrefix("Yabomish") ? comp : "Yabomish"
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return NSHomeDirectory() + "/Library/Application Support/\(dirName)"
        }
        let dir = appSupport.appendingPathComponent(dirName)
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
