import Foundation

/// 語料下載：從 GitHub Release 下載語料 zip 並解壓至 Application Support
enum DataDownloader {
    static let dataURL = "https://github.com/user/yabomish-data/releases/download/v0.3.0/yabomish-data-v0.3.0.zip"
    static let supportDir = NSHomeDirectory() + "/Library/Application Support/YabomishIM"
    private static let marker = "bigram_boost.json"

    static var isDataAvailable: Bool {
        FileManager.default.fileExists(atPath: supportDir + "/" + marker)
    }

    static func ensureData(completion: @escaping (Bool) -> Void) {
        if isDataAvailable { completion(true); return }

        NSLog("YabomishIM: 語料不存在，開始下載 %@", dataURL)
        guard let url = URL(string: dataURL) else { completion(false); return }

        let task = URLSession.shared.downloadTask(with: url) { tmpURL, response, error in
            guard let tmpURL = tmpURL, error == nil else {
                NSLog("YabomishIM: 下載失敗 — %@", error?.localizedDescription ?? "unknown")
                completion(false)
                return
            }
            do {
                let fm = FileManager.default
                try fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
                let zipPath = supportDir + "/data.zip"
                if fm.fileExists(atPath: zipPath) { try fm.removeItem(atPath: zipPath) }
                try fm.moveItem(atPath: tmpURL.path, toPath: zipPath)

                // unzip
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                proc.arguments = ["-o", zipPath, "-d", supportDir]
                try proc.run()
                proc.waitUntilExit()

                try? fm.removeItem(atPath: zipPath)
                let ok = fm.fileExists(atPath: supportDir + "/" + marker)
                NSLog("YabomishIM: 語料下載%@", ok ? "完成" : "失敗（解壓後找不到檔案）")
                completion(ok)
            } catch {
                NSLog("YabomishIM: 解壓失敗 — %@", error.localizedDescription)
                completion(false)
            }
        }
        task.resume()
    }
}
