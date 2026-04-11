import Cocoa
import InputMethodKit

class NSManualApplication: NSApplication {
    private let appDelegate = AppDelegate()
    override init() {
        super.init()
        self.delegate = appDelegate
    }
    required init?(coder: NSCoder) { fatalError() }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    static var server = IMKServer()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Input methods still need an activatable policy when showing prefs/open panels.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let name = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
        Self.server = IMKServer(name: name, bundleIdentifier: Bundle.main.bundleIdentifier)
        DebugLog.log("YabomishIM: Server started, connection=\(name ?? "nil")")
        let ver = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        DebugLog.log("YabomishIM: build=\(ver), domains=\(WikiCorpus.shared.domainBinCount)")
        YabomishPrefs.migrateLegacyPrefs()
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.yabomish.prefsChanged"), object: nil, queue: .main) { _ in WikiCorpus.shared.reloadDomains() }
    }
}
