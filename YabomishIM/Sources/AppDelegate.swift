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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let name = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
        Self.server = IMKServer(name: name, bundleIdentifier: Bundle.main.bundleIdentifier)
        NSLog("YabomishIM: Server started, connection=%@", name ?? "nil")
    }
}
