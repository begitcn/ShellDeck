import Foundation
import AppKit

public enum UpdateCheckStatus: Equatable {
    case idle
    case checking
    case updateAvailable(version: String, notes: String?, downloadUrl: String?, releaseUrl: String?)
    case upToDate
    case error(String)
}

@MainActor
@Observable
public final class UpdateService {
    public static let shared = UpdateService()
    
    // UI state machine
    public var checkStatus: UpdateCheckStatus = .idle
    public var updateAvailable = false
    public var latestVersion: String?
    public var releaseNotes: String?
    public var releaseUrl: String?
    public var downloadUrl: String?
    
    // Download state
    public var isDownloading = false
    public var downloadProgress: Double = 0.0
    public var downloadError: String? = nil
    public var downloadedFileUrl: URL? = nil
    
    private let githubRepo = "begitcn/ShellDeck"
    private var downloadManager: DownloadManager?
    
    private let lastCheckedKey = "ShellDeck_LastCheckedDate"
    private let ignoredVersionKey = "ShellDeck_IgnoredVersion"
    
    public var currentVersion: String {
        "0.0.1" // Hardcoded to 0.0.1 for testing updates!
    }
    
    private init() {}
    
    /// Resets the status to idle.
    public func resetStatus() {
        checkStatus = .idle
        downloadError = nil
    }
    
    /// Checks for updates.
    /// - Parameter manual: If true, ignores the 24-hour cache limit.
    public func checkForUpdates(manual: Bool = false) async {
        guard checkStatus != .checking else { return }
        
        let now = Date()
        if !manual {
            // Respect GitHub API Rate limits: check cache first.
            if let lastChecked = UserDefaults.standard.object(forKey: lastCheckedKey) as? Date {
                let hoursSinceLastCheck = now.timeIntervalSince(lastChecked) / 3600.0
                if hoursSinceLastCheck < 24.0 {
                    // Less than 24 hours since last check, skip and stay idle.
                    checkStatus = .idle
                    return
                }
            }
        } else {
            // Throttle manual check to avoid spamming the button.
            if let lastChecked = UserDefaults.standard.object(forKey: lastCheckedKey) as? Date,
               now.timeIntervalSince(lastChecked) < 5.0 {
                // If throttled, don't hit the API but show cached state if update is already known
                if updateAvailable, let tag = latestVersion {
                    checkStatus = .updateAvailable(version: tag, notes: releaseNotes, downloadUrl: downloadUrl, releaseUrl: releaseUrl)
                } else {
                    checkStatus = .upToDate
                }
                return
            }
        }
        
        checkStatus = .checking
        downloadError = nil
        
        let urlString = "https://api.github.com/repos/\(githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else {
            checkStatus = .error("无效的更新检测 URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("ShellDeck-Updater", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                checkStatus = .error("无效的服务器响应")
                return
            }
            
            if httpResponse.statusCode == 403 {
                checkStatus = .error("请求次数超限 (GitHub API Rate Limit)")
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                checkStatus = .error("服务器错误 (状态码 \(httpResponse.statusCode))")
                return
            }
            
            struct Release: Codable {
                let tag_name: String
                let name: String?
                let body: String?
                let html_url: String
                struct Asset: Codable {
                    let name: String
                    let browser_download_url: String
                }
                let assets: [Asset]
            }
            
            let release = try JSONDecoder().decode(Release.self, from: data)
            let tag = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            
            // Check if user ignored this version (only respect for automatic checks)
            if !manual {
                let ignoredVersion = UserDefaults.standard.string(forKey: ignoredVersionKey) ?? ""
                if ignoredVersion == tag {
                    checkStatus = .idle
                    return
                }
            }
            
            let isNew = isVersion(tag, greaterThan: currentVersion)
            
            // Find matched architecture asset:
            #if arch(arm64)
            let targetArch = "aarch64"
            #else
            let targetArch = "x86_64"
            #endif
            
            let matchedAsset = release.assets.first { asset in
                asset.name.contains(targetArch) && asset.name.hasSuffix(".dmg")
            } ?? release.assets.first { asset in
                asset.name.hasSuffix(".dmg")
            }
            
            self.latestVersion = tag
            self.releaseNotes = release.body
            self.releaseUrl = release.html_url
            self.downloadUrl = matchedAsset?.browser_download_url
            self.updateAvailable = isNew
            
            if isNew {
                self.checkStatus = .updateAvailable(
                    version: tag,
                    notes: release.body,
                    downloadUrl: matchedAsset?.browser_download_url,
                    releaseUrl: release.html_url
                )
            } else {
                self.checkStatus = .upToDate
            }
            
            // Cache the last check date only if API call succeeded.
            UserDefaults.standard.set(now, forKey: lastCheckedKey)
        } catch {
            self.checkStatus = .error(error.localizedDescription)
            print("Failed to check for updates: \(error)")
        }
    }
    
    public func ignoreVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: ignoredVersionKey)
        updateAvailable = false
        checkStatus = .idle
    }
    
    public func downloadAndInstall() {
        guard let downloadUrlString = downloadUrl, let url = URL(string: downloadUrlString) else {
            downloadError = "无效的下载链接"
            return
        }
        
        isDownloading = true
        downloadProgress = 0.0
        downloadError = nil
        downloadedFileUrl = nil
        
        let manager = DownloadManager()
        self.downloadManager = manager
        
        manager.onProgress = { [weak self] progress in
            guard let self = self else { return }
            Task { @MainActor in
                self.downloadProgress = progress
            }
        }
        
        manager.onCompletion = { [weak self] fileUrl, error in
            guard let self = self else { return }
            Task { @MainActor in
                self.isDownloading = false
                if let error = error {
                    self.downloadError = error.localizedDescription
                    self.checkStatus = .error("下载失败: \(error.localizedDescription)")
                } else if let fileUrl = fileUrl {
                    self.downloadedFileUrl = fileUrl
                    do {
                        try await self.installAndRestart(dmgUrl: fileUrl)
                    } catch {
                        self.downloadedFileUrl = nil // Reset so UI exits the stuck loading screen!
                        self.downloadError = "自动静默安装失败: \(error.localizedDescription)"
                        self.checkStatus = .error("静默安装失败: \(error.localizedDescription)。我们将为您打开挂载盘进行手动安装。")
                        // Fallback: manually mount DMG so user can install
                        self.openInstaller(at: fileUrl)
                    }
                }
            }
        }
        
        manager.startDownload(url: url)
    }
    
    public func cancelDownload() {
        downloadManager?.cancel()
        isDownloading = false
        downloadProgress = 0.0
    }
    
    public func openInstaller(at url: URL) {
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Background Installer & Restarter
    
    private func installAndRestart(dmgUrl: URL) async throws {
        // Offload the heavy file operations and mounting to a background task detached from the MainActor
        try await Task.detached(priority: .userInitiated) {
            // 1. Mount the DMG silently in the background
            let mountPoint = try await self.mountDMG(url: dmgUrl)
            defer {
                Task {
                    try? await self.unmountDMG(mountPoint: mountPoint)
                }
            }
            
            // 2. Locate ShellDeck.app inside the mounted volume
            let mountedAppUrl = mountPoint.appendingPathComponent("ShellDeck.app")
            guard FileManager.default.fileExists(atPath: mountedAppUrl.path) else {
                throw NSError(domain: "UpdaterError", code: 404, userInfo: [NSLocalizedDescriptionKey: "挂载盘中未找到 ShellDeck.app"])
            }
            
            // 3. Get the path of the current running app
            let currentAppUrl = Bundle.main.bundleURL // e.g. /Applications/ShellDeck.app
            let appsDirectory = currentAppUrl.deletingLastPathComponent() // e.g. /Applications
            
            // 4. Create a temporary path in the target directory
            let tempAppUrl = appsDirectory.appendingPathComponent("ShellDeck.app.new")
            
            // Clean up any stale temp app
            if FileManager.default.fileExists(atPath: tempAppUrl.path) {
                try? FileManager.default.removeItem(at: tempAppUrl)
            }
            
            // 5. Copy the new app bundle to the target directory
            try FileManager.default.copyItem(at: mountedAppUrl, to: tempAppUrl)
            
            // 6. Perform the atomic swap
            let backupAppUrl = appsDirectory.appendingPathComponent("ShellDeck.app.old")
            if FileManager.default.fileExists(atPath: backupAppUrl.path) {
                try? FileManager.default.removeItem(at: backupAppUrl)
            }
            
            // Rename current running app to .old
            try FileManager.default.moveItem(at: currentAppUrl, to: backupAppUrl)
            
            do {
                // Move new app into place
                try FileManager.default.moveItem(at: tempAppUrl, to: currentAppUrl)
                // Delete the old backup app bundle in the background
                try? FileManager.default.removeItem(at: backupAppUrl)
            } catch {
                // Revert rename if it failed
                try? FileManager.default.moveItem(at: backupAppUrl, to: currentAppUrl)
                throw error
            }
            
            // 7. Restart the application
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = []
            try await NSWorkspace.shared.openApplication(at: currentAppUrl, configuration: configuration)
            
            // Exit current process on the MainActor
            await MainActor.run {
                NSApp.terminate(nil)
            }
        }.value
    }
    
    nonisolated private func mountDMG(url: URL) async throws -> URL {
        try await Task.detached(priority: .background) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["attach", "-nobrowse", "-readonly", "-plist", url.path]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "UpdaterError", code: 500, userInfo: [NSLocalizedDescriptionKey: "hdiutil attach 挂载失败，错误码: \(process.terminationStatus)"])
            }
            
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            
            // Parse plist output to find mount point
            if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let systemEntities = plist["system-entities"] as? [[String: Any]] {
                for entity in systemEntities {
                    if let mountPoint = entity["mount-point"] as? String {
                        return URL(fileURLWithPath: mountPoint)
                    }
                }
            }
            
            // Fallback search in /Volumes
            let volumesUrl = URL(fileURLWithPath: "/Volumes")
            let volumes = try FileManager.default.contentsOfDirectory(at: volumesUrl, includingPropertiesForKeys: nil)
            for volume in volumes {
                if volume.lastPathComponent.contains("ShellDeck") {
                    return volume
                }
            }
            
            throw NSError(domain: "UpdaterError", code: 404, userInfo: [NSLocalizedDescriptionKey: "无法解析 DMG 挂载点"])
        }.value
    }
    
    nonisolated private func unmountDMG(mountPoint: URL) async throws {
        try await Task.detached(priority: .background) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["detach", mountPoint.path, "-force"]
            try process.run()
            process.waitUntilExit()
        }.value
    }
    
    private func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let components1 = v1.split(separator: ".").compactMap { Int($0) }
        let components2 = v2.split(separator: ".").compactMap { Int($0) }
        
        let count = max(components1.count, components2.count)
        for i in 0..<count {
            let val1 = i < components1.count ? components1[i] : 0
            let val2 = i < components2.count ? components2[i] : 0
            if val1 > val2 {
                return true
            } else if val1 < val2 {
                return false
            }
        }
        return false
    }
}

// MARK: - DownloadManager

private final class DownloadManager: NSObject, URLSessionDownloadDelegate {
    var onProgress: ((Double) -> Void)?
    var onCompletion: ((URL?, Error?) -> Void)?
    
    private var session: URLSession!
    private var downloadTask: URLSessionDownloadTask?
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
    }
    
    func startDownload(url: URL) {
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }
    
    func cancel() {
        downloadTask?.cancel()
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress?(progress)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = downloadTask.originalRequest?.url?.lastPathComponent ?? "ShellDeck-update.dmg"
        let destinationUrl = tempDir.appendingPathComponent(filename)
        
        do {
            if FileManager.default.fileExists(atPath: destinationUrl.path) {
                try FileManager.default.removeItem(at: destinationUrl)
            }
            try FileManager.default.moveItem(at: location, to: destinationUrl)
            onCompletion?(destinationUrl, nil)
        } catch {
            onCompletion?(nil, error)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onCompletion?(nil, error)
        }
    }
}
