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
    /// prefsChanged 去抖用：連續通知只觸發最後一次網域詞庫重載
    private static var reloadDomainsWork: DispatchWorkItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Input methods still need an activatable policy when showing prefs/open panels.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let name = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
        Self.server = IMKServer(name: name, bundleIdentifier: Bundle.main.bundleIdentifier)
        DebugLog.log("YabomishIM: Server started, connection=\(name ?? "nil")")
        let ver = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        // 不在此觸碰 WikiCorpus.shared——其 init 會同步載入全部語料，避免拉慢啟動
        DebugLog.log("YabomishIM: build=\(ver)")
        YabomishPrefs.migrateLegacyPrefs()
        YabomishInputController.startBackgroundTasks()
        // ,,B/,,F 的 app 切換歷史：越早開始記錄越完整
        AppSwitchTracker.warmUp()
        // YabomishPrefs 儲存快捷碼／匯入字表後會廣播此通知，等同 ,,RL：重載字表與自訂指令
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.yabomish.reloadTables"), object: nil, queue: .main
        ) { _ in Self.reloadTables() }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.yabomish.prefsChanged"), object: nil, queue: .main
        ) { _ in
            // 去抖 0.5s：連續 prefsChanged（如拖曳字級）只重載一次網域詞庫
            Self.reloadDomainsWork?.cancel()
            let work = DispatchWorkItem { WikiCorpus.shared.reloadDomains() }
            Self.reloadDomainsWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    /// ,,RL 語意：重載字表（含 tables/*.txt 擴充表）與自訂指令、snippets
    private static func reloadTables() {
        YabomishInputController.reloadTable()
        CommaCommandRunner.reload()
        #if !MINIMAL
        UserSnippets.shared.reload()
        #endif
    }
}
