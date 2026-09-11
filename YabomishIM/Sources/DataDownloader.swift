import Foundation
import CommonCrypto

/// 語料下載：從 GitHub Release 下載語料 zip 並解壓至 Application Support
///
/// 下載網址與預期 SHA-256 改由 Bundle 資源 `corpus_manifest.json` 驅動；
/// 更新語料時以 tools/make_corpus_manifest.py 重新產生清單即可，不必改 Swift。
/// 清單缺失或無法解析時，退回下列硬編碼後備常數。
enum DataDownloader {
    /// 後備常數：manifest 缺失或解析失敗時使用（對應 0.3.59 版語料）
    static let fallbackURL = "https://github.com/FakeRocket543/yabomish/releases/download/v0.3.59/yabomish-corpus-lite-0.3.59.zip"
    /// 後備常數：Expected SHA-256 of the zip file — update when releasing new data
    static let fallbackSHA256 = "c020b544ca5376b675e68a07d0d8d26b50cff6c484a4b22267b88c00607210c3"
    /// 預留值：沿用舊版語意，設為此值時略過 SHA-256 驗證
    private static let shaPlaceholder = "UPDATE_THIS_HASH_ON_RELEASE"

    private struct CorpusManifest: Decodable {
        let version: String?
        let url: String?
        let sha256: String?
        let fileName: String?
        /// corpusVariant == "full" 時使用（全量語料＋專業詞典）；缺漏時退回 lite
        let full: FullEntry?

        struct FullEntry: Decodable {
            let url: String?
            let sha256: String?
        }
    }

    private static let manifest: CorpusManifest? = {
        guard let url = Bundle.main.url(forResource: "corpus_manifest", withExtension: "json") else {
            DebugLog.log("DataDownloader: 找不到 corpus_manifest.json，改用內建後備常數")
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            DebugLog.log("DataDownloader: corpus_manifest.json 讀取失敗，改用內建後備常數")
            return nil
        }
        do {
            return try JSONDecoder().decode(CorpusManifest.self, from: data)
        } catch {
            DebugLog.log("DataDownloader: corpus_manifest.json 解析失敗（\(error.localizedDescription)），改用內建後備常數")
            return nil
        }
    }()

    /// 語料 zip 下載網址。url 與 sha256 視為一組：manifest 任一缺漏時整組
    /// 退回後備常數，避免「新網址配舊雜湊」造成下載永久失敗。
    /// corpusVariant == "full"（安裝時選「完整」）且 manifest 有 full 段時用全量語料；
    /// manifest 缺 full 段則退回 lite zip（優雅降級，避免 404 空手而回）。
    static let dataURL: String = {
        if YabomishPrefs.corpusVariant == "full",
           let u = manifest?.full?.url, let s = manifest?.full?.sha256, !s.isEmpty {
            return u
        }
        if let u = manifest?.url, let s = manifest?.sha256, !s.isEmpty { return u }
        return fallbackURL
    }()
    /// 預期 SHA-256；空字串或預留值代表略過驗證（語意同舊版 UPDATE_THIS_HASH_ON_RELEASE）
    static let expectedSHA256: String = {
        if YabomishPrefs.corpusVariant == "full",
           let u = manifest?.full?.url, let s = manifest?.full?.sha256, !s.isEmpty {
            return s
        }
        if let u = manifest?.url, let s = manifest?.sha256, !s.isEmpty { return s }
        return fallbackSHA256
    }()
    /// 語料版本（僅供記錄用）
    static let manifestVersion = manifest?.version ?? "0.3.59"

    static let supportDir = AppConstants.sharedDir
    private static let marker = "bigram.bin"

    /// 下載進行中旗標（含鎖）：activateServer 每次切換視窗都會觸發 ensureData
    private static let downloadLock = NSLock()
    private static var isDownloading = false

    static var isDataAvailable: Bool {
        // Check App Support first, then bundle Resources
        if FileManager.default.fileExists(atPath: supportDir + "/" + marker) { return true }
        if Bundle.main.path(forResource: "bigram", ofType: "bin") != nil { return true }
        return false
    }

    /// 串流計算 SHA-256：FileHandle 分段讀取，避免整檔載入記憶體，
    /// 也不受 CC_LONG（32-bit 長度）對超大檔的截斷影響
    private static func sha256(of url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var ctx = CC_SHA256_CTX()
        CC_SHA256_Init(&ctx)
        let chunkSize = 1 << 20
        while true {
            let chunk = fh.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            let ok = chunk.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int32 in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return CC_SHA256_Update(&ctx, base, CC_LONG(chunk.count))
            }
            guard ok == 1 else { return nil }
            if chunk.count < chunkSize { break }
        }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&hash, &ctx)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Validate that no zip entry escapes the target directory via path traversal
    private static func safeUnzip(zipPath: String, destDir: String) -> Bool {
        // `zipinfo -l` prints an attributes column: "-rwxr-xr-x" for files,
        // "drwxr-xr-x" for dirs, "lrwxr-xr-x" for symlinks. Reject symlinks —
        // classic zip-slip variant: an "l" entry pointing at /etc/... followed
        // by a file entry of the same name makes unzip -o write through it.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        proc.arguments = ["-l", zipPath]
        let pipe = Pipe()
        proc.standardOutput = pipe
        do { try proc.run() } catch { return false }
        proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // zipinfo -l row: perms ver OS size type-method cmp-size method date time name
        // name = everything after the 9th column (names may contain spaces).
        // Footer rows ("N files, ...") lack a perms-looking first column — skipped.
        for line in output.split(separator: "\n").dropFirst(2) {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 10 else { continue } // header/footer lines
            let perms = cols[0]
            guard perms.count == 10 else { continue }
            let first = perms[perms.startIndex]
            guard first == "-" || first == "l" || first == "d" else { continue }
            let name = cols.dropFirst(9).joined(separator: " ")
            if perms.hasPrefix("l") {
                DebugLog.log("DataDownloader: rejected symlink entry: \(name)")
                return false
            }
            if name.contains("..") || name.hasPrefix("/") {
                DebugLog.log("DataDownloader: rejected unsafe zip entry: \(name)")
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

        // 防重複下載：activateServer 每次切換視窗都會觸發，下載期間的重入
        // 直接略過（由進行中的下載負責回報）
        downloadLock.lock()
        if isDownloading {
            downloadLock.unlock()
            DebugLog.log("YabomishIM: 語料下載進行中，略過重複觸發")
            completion(false); return
        }
        isDownloading = true
        downloadLock.unlock()
        let finish: (Bool) -> Void = { ok in
            downloadLock.lock(); isDownloading = false; downloadLock.unlock()
            completion(ok)
        }

        DebugLog.log("YabomishIM: 語料不存在（v\(manifestVersion)），開始下載 \(dataURL)")
        guard let url = URL(string: dataURL) else { finish(false); return }

        let task = URLSession.shared.downloadTask(with: url) { tmpURL, response, error in
            guard let tmpURL = tmpURL, error == nil else {
                DebugLog.log("YabomishIM: 下載失敗 — \(error?.localizedDescription ?? "unknown")")
                finish(false)
                return
            }
            let fm = FileManager.default
            do {
                try fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
                let zipPath = supportDir + "/data.zip"
                if fm.fileExists(atPath: zipPath) { try fm.removeItem(atPath: zipPath) }
                try fm.moveItem(atPath: tmpURL.path, toPath: zipPath)

                // Integrity check — manifest 的 sha256 為空（或為預留值）時略過，
                // 語意同舊版 UPDATE_THIS_HASH_ON_RELEASE 分支
                if expectedSHA256.isEmpty || expectedSHA256 == shaPlaceholder {
                    DebugLog.log("YabomishIM: 未設定預期 SHA-256，略過完整性驗證")
                } else {
                    guard let actual = sha256(of: URL(fileURLWithPath: zipPath)) else {
                        DebugLog.log("YabomishIM: SHA-256 計算失敗")
                        try? fm.removeItem(atPath: zipPath)
                        finish(false); return
                    }
                    guard actual == expectedSHA256 else {
                        DebugLog.log("YabomishIM: SHA-256 不符 expected=\(expectedSHA256) actual=\(actual)")
                        try? fm.removeItem(atPath: zipPath)
                        finish(false); return
                    }
                }

                // 解壓至同目錄 staging（.staging-<uuid>）：驗證檔案齊全後才逐檔
                // rename 進 supportDir、marker 最後移入。解壓中途死掉只留 staging
                // 殘骸（重試會清掉），不會出現「永久殘缺且無修復路徑」的語料。
                let staging = supportDir + "/.staging-\(UUID().uuidString)"
                try fm.createDirectory(atPath: staging, withIntermediateDirectories: true)
                guard safeUnzip(zipPath: zipPath, destDir: staging) else {
                    DebugLog.log("YabomishIM: 解壓失敗或偵測到不安全路徑")
                    try? fm.removeItem(atPath: zipPath)
                    try? fm.removeItem(atPath: staging)
                    finish(false); return
                }
                guard fm.fileExists(atPath: staging + "/" + marker) else {
                    DebugLog.log("YabomishIM: 語料 zip 缺少 \(marker)")
                    try? fm.removeItem(atPath: zipPath)
                    try? fm.removeItem(atPath: staging)
                    finish(false); return
                }
                // marker 排最後移入：全部就位前 isDataAvailable 維持 false
                let files = ((try? fm.contentsOfDirectory(atPath: staging)) ?? [])
                    .sorted { a, b in
                        if a == marker { return false }
                        if b == marker { return true }
                        return a < b
                    }
                for f in files {
                    let dst = supportDir + "/" + f
                    if fm.fileExists(atPath: dst) { try fm.removeItem(atPath: dst) }
                    try fm.moveItem(atPath: staging + "/" + f, toPath: dst)
                }
                try? fm.removeItem(atPath: staging)

                try? fm.removeItem(atPath: zipPath)
                DebugLog.log("YabomishIM: 語料下載完成")
                finish(true)
            } catch {
                DebugLog.log("YabomishIM: 語料安裝失敗 — \(error.localizedDescription)")
                // 清掉可能殘留的 staging 目錄
                if let leftovers = try? fm.contentsOfDirectory(atPath: supportDir) {
                    for f in leftovers where f.hasPrefix(".staging-") {
                        try? fm.removeItem(atPath: supportDir + "/" + f)
                    }
                }
                finish(false)
            }
        }
        task.resume()
    }
}
