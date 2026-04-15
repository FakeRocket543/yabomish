import Foundation
import CommonCrypto

/// 語料下載：從 GitHub Release 下載語料 zip 並解壓至 Application Support
enum DataDownloader {
    static let dataURL = "https://github.com/user/yabomish-data/releases/download/v0.3.0/yabomish-data-v0.3.0.zip"
    static let supportDir = AppConstants.sharedDir
    private static let marker = "bigram.bin"
    /// Expected SHA-256 of the zip file — update when releasing new data
    static let expectedSHA256 = "UPDATE_THIS_HASH_ON_RELEASE"

    static var isDataAvailable: Bool {
        // Check App Support first, then bundle Resources
        if FileManager.default.fileExists(atPath: supportDir + "/" + marker) { return true }
        if Bundle.main.path(forResource: "bigram", ofType: "bin") != nil { return true }
        return false
    }

    private static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Validate that no zip entry escapes the target directory via path traversal
    private static func safeUnzip(zipPath: String, destDir: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        proc.arguments = ["-1", zipPath]
        let pipe = Pipe()
        proc.standardOutput = pipe
        do { try proc.run() } catch { return false }
        proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // Reject if any entry contains ".." or starts with "/"
        for line in output.split(separator: "\n") {
            let entry = String(line)
            if entry.contains("..") || entry.hasPrefix("/") {
                DebugLog.log("DataDownloader: rejected unsafe zip entry: \(entry)")
                return false
            }
        }
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", zipPath, "-d", destDir]
        do { try unzip.run() } catch { return false }
        unzip.waitUntilExit()
        return unzip.terminationStatus == 0
    }

    static func ensureData(completion: @escaping (Bool) -> Void) {
        if isDataAvailable { completion(true); return }

        DebugLog.log("YabomishIM: 語料不存在，開始下載 \(dataURL)")
        guard let url = URL(string: dataURL) else { completion(false); return }

        let task = URLSession.shared.downloadTask(with: url) { tmpURL, response, error in
            guard let tmpURL = tmpURL, error == nil else {
                DebugLog.log("YabomishIM: 下載失敗 — \(error?.localizedDescription ?? "unknown")")
                completion(false)
                return
            }
            do {
                let fm = FileManager.default
                try fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
                let zipPath = supportDir + "/data.zip"
                if fm.fileExists(atPath: zipPath) { try fm.removeItem(atPath: zipPath) }
                try fm.moveItem(atPath: tmpURL.path, toPath: zipPath)

                // Integrity check
                if expectedSHA256 != "UPDATE_THIS_HASH_ON_RELEASE" {
                    guard let actual = sha256(of: URL(fileURLWithPath: zipPath)) else {
                        DebugLog.log("YabomishIM: SHA-256 計算失敗")
                        try? fm.removeItem(atPath: zipPath)
                        completion(false); return
                    }
                    guard actual == expectedSHA256 else {
                        DebugLog.log("YabomishIM: SHA-256 不符 expected=\(expectedSHA256) actual=\(actual)")
                        try? fm.removeItem(atPath: zipPath)
                        completion(false); return
                    }
                }

                // Safe extraction with path traversal check
                guard safeUnzip(zipPath: zipPath, destDir: supportDir) else {
                    DebugLog.log("YabomishIM: 解壓失敗或偵測到不安全路徑")
                    try? fm.removeItem(atPath: zipPath)
                    completion(false); return
                }

                try? fm.removeItem(atPath: zipPath)
                let ok = fm.fileExists(atPath: supportDir + "/" + marker)
                DebugLog.log("YabomishIM: 語料下載\(ok ? "完成" : "失敗（解壓後找不到檔案）")")
                completion(ok)
            } catch {
                DebugLog.log("YabomishIM: 解壓失敗 — \(error.localizedDescription)")
                completion(false)
            }
        }
        task.resume()
    }
}
