import Foundation
import AppKit

/// 蝦頭方向即時套用：把已安裝輸入法 Resources 裡的 icon_left.tiff／icon_right.tiff
/// 覆寫成輸入法實際載入的 icon.tiff（安裝時由 yabomish.sh 固定，這裡提供事後切換）。
/// 安裝路徑與 yabomish.sh 的 INSTALL_DIR 一樣寫死——Prefs 是本機管理工具，不做動態解析。
/// 「/Library/Input Methods」需 root：改圖示時以 Process 叫 /usr/bin/osascript 跑
/// do shell script ... with administrator privileges（系統標準授權對話框）；
/// 重啟輸入法（killall + open）則不需要權限。
enum IconApply {
    /// 已安裝輸入法路徑（與 yabomish.sh 一致的字面路徑）
    private static let imAppPath = "/Library/Input Methods/YabomishIM.app"
    private static let resourcesDir = imAppPath + "/Contents/Resources"
    /// 輸入法實際載入的圖示檔名（固定不變，方向圖示只是覆寫到這個檔）
    private static let installedIconPath = resourcesDir + "/icon.tiff"

    /// 套用結果
    enum Outcome: Equatable {
        /// 已透過管理者授權複製完成，輸入法重啟後生效
        case applied
        /// 安裝目錄的 icon.tiff 內容已一致——免授權、免重啟
        case alreadyCurrent
    }

    enum ApplyError: LocalizedError {
        case appMissing              // 找不到已安裝的輸入法
        case sourceMissing(String)   // 來源 tiff 不存在（舊版安裝）
        case badDirection(String)    // 未知的方向字串（防呆）
        case userCancelled           // 使用者在授權對話框按了取消
        case copyFailed(String)      // osascript／cp 真的失敗

        var errorDescription: String? {
            switch self {
            case .appMissing:
                return "找不到已安裝的輸入法：\n\(imAppPath)"
            case .sourceMissing(let name):
                return "安裝目錄缺少 \(name)（可能是舊版安裝），請重新執行 yabomish.sh 安裝後再切換。"
            case .badDirection(let d):
                return "未知的圖示方向：「\(d)」"
            case .userCancelled:
                return "已取消授權，圖示維持原方向。"
            case .copyFailed(let detail):
                return "套用失敗：\n\(detail)"
            }
        }
    }

    // MARK: - 查詢

    /// 方向 id → 安裝目錄裡對應的來源 tiff 檔名
    private static func sourceName(for direction: String) -> String? {
        switch direction {
        case "left":  return "icon_left.tiff"
        case "right": return "icon_right.tiff"
        default:      return nil
        }
    }

    /// 安裝目錄的 icon.tiff 是否已與目標方向的來源圖一致（內容逐位元組比對）。
    /// 一致時呼叫端可完全跳過授權對話框。
    static func isCurrent(direction: String) -> Bool {
        guard let name = sourceName(for: direction),
              let cur = try? Data(contentsOf: URL(fileURLWithPath: installedIconPath)), !cur.isEmpty,
              let want = try? Data(contentsOf: URL(fileURLWithPath: resourcesDir + "/" + name))
        else { return false }
        return cur == want
    }

    // MARK: - 套用

    /// 套用方向：必要時跳出管理者授權，把來源 tiff 覆寫成 icon.tiff。
    /// 同步執行（Process 阻塞到 osascript 結束；由外層放在背景執行緒呼叫）。
    /// 成功後由呼叫端接 restartInputMethod() 重啟輸入法讓圖示生效。
    @discardableResult
    static func apply(direction: String) -> Result<Outcome, ApplyError> {
        let fm = FileManager.default
        guard fm.fileExists(atPath: imAppPath) else { return .failure(.appMissing) }
        guard let name = sourceName(for: direction) else { return .failure(.badDirection(direction)) }
        let srcPath = resourcesDir + "/" + name
        guard fm.fileExists(atPath: srcPath) else { return .failure(.sourceMissing(name)) }
        // 內容已一致：完全不打擾使用者（不出授權對話框）
        if isCurrent(direction: direction) { return .success(.alreadyCurrent) }

        // 授權步驟：osascript -e 'do shell script "..." with administrator privileges'
        // 引數一律以陣列傳入（路徑含空白「Input Methods」也不怕外層誤拆）。
        // 內層 shell 命令以雙引號包住含空白路徑，而這些雙引號對 AppleScript 字串
        // 來說是特殊字元，必須寫成 \"（Swift 原始碼裡是 \\\"）跳脫。
        let shell = "[ -f \\\"\(srcPath)\\\" ] && cp -f \\\"\(srcPath)\\\" \\\"\(installedIconPath)\\\" || exit 1"
        let script = "do shell script \"\(shell)\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        do {
            try proc.run()
        } catch {
            return .failure(.copyFailed(String(describing: error)))
        }
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        if proc.terminationStatus == 0 {
            // 複製後再比對一次內容，確保真的換掉了
            return isCurrent(direction: direction) ? .success(.applied)
                                                   : .failure(.copyFailed("複製完成但內容驗證不符"))
        }
        // 取消偵測：使用者按掉授權對話框時 osascript 結束碼非 0、
        // stderr 含「User canceled」／「cancelled」（拼法隨語系）或錯誤碼 (-128)。
        let stderrText = String(decoding: stderrData, as: UTF8.self)
        if stderrText.range(of: "cancel", options: .caseInsensitive) != nil
            || stderrText.contains("(-128)") {
            return .failure(.userCancelled)
        }
        return .failure(.copyFailed(stderrText.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    /// 免權限重啟輸入法：killall（沒在跑也無妨）＋ open（TIS 視需求會自動拉起）。
    /// 選單圖示由 TIS 依輸入來源快取，重啟輸入法程序後通常會更新；
    /// 必要時切換一次輸入法即重繪（UI 文案已註明）。
    static func restartInputMethod() {
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        kill.arguments = ["YabomishIM"]
        try? kill.run()
        kill.waitUntilExit()  // 忽略結果：輸入法本來就可能沒在跑
        // NSWorkspace.open 應在主執行緒呼叫（由外層於 main queue 呼叫本函式）
        NSWorkspace.shared.open(URL(fileURLWithPath: imAppPath))
    }
}
