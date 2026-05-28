import Foundation
import AppKit
import Observation

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
    
    private var downloadManager: DownloadManager?
    
    public var currentVersion: String {
        "0.0.4"
    }
    
    private init() {}
    
    public func resetStatus() {
        checkStatus = .idle
        downloadError = nil
    }
    
    public func checkForUpdates(manual: Bool = false) async {
        guard checkStatus != .checking else { return }
        
        checkStatus = .checking
        downloadError = nil
        
        guard let url = URL(string: "https://shelldeck.782389.xyz") else {
            checkStatus = .error("无效的更新检测 URL")
            return
        }
        
        let request = URLRequest(url: url)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                checkStatus = .error("服务器错误")
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
            let isNew = isVersion(tag, greaterThan: currentVersion)
            
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
        } catch {
            self.checkStatus = .error("检查失败")
        }
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
                        try await UpdateService.silentInstall(dmgUrl: fileUrl)
                    } catch {
                        self.downloadedFileUrl = nil
                        self.downloadError = "自动安装失败，将打开 DMG 手动安装"
                        self.checkStatus = .error("安装失败")
                        NSWorkspace.shared.open(fileUrl)
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
    
    // MARK: - Silent Install
    
    nonisolated private static func silentInstall(dmgUrl: URL) async throws {
        let mountPoint = try await mountDMG(dmgUrl: dmgUrl)
        defer { try? unmountDMG(mountPoint: mountPoint) }
        
        let items = try FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        guard let mountedApp = items.first else {
            throw NSError(domain: "UpdaterError", code: 404, userInfo: nil)
        }
        
        let current = Bundle.main.bundleURL
        let newPath = current.deletingLastPathComponent().appendingPathComponent("ShellDeck.app.new")
        
        try? FileManager.default.removeItem(at: newPath)
        try FileManager.default.copyItem(at: mountedApp, to: newPath)
        
        let script = """
        #!/bin/bash
        sleep 4
        rm -rf "\(current.path)"
        mv "\(newPath.path)" "\(current.path)"
        rm -f "\(dmgUrl.path)" 2>/dev/null
        hdiutil detach "\(mountPoint.path)" -force 2>/dev/null
        open "\(current.path)"
        """
        let scriptUrl = FileManager.default.temporaryDirectory.appendingPathComponent("sd-up-\(UUID().uuidString).sh")
        try script.write(to: scriptUrl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptUrl.path)
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptUrl.path]
        try proc.run()
        
        await MainActor.run { exit(0) }
    }
    
    nonisolated private static func mountDMG(dmgUrl: URL) async throws -> URL {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        proc.arguments = ["attach", "-nobrowse", "-readonly", "-plist", dmgUrl.path]
        let out = Pipe()
        proc.standardOutput = out
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "UpdaterError", code: 500, userInfo: nil)
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mp = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw NSError(domain: "UpdaterError", code: 404, userInfo: nil)
        }
        return URL(fileURLWithPath: mp)
    }
    
    nonisolated private static func unmountDMG(mountPoint: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        proc.arguments = ["detach", mountPoint.path, "-force"]
        try proc.run()
        proc.waitUntilExit()
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
