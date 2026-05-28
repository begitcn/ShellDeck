import Foundation
import Observation
import Citadel
import NIOCore

enum SFTPError: LocalizedError {
    case notConnected
    case downloadFailed(Error)
    case uploadFailed(Error)
    case listFailed(Error)
    case deleteFailed(Error)
    case createDirectoryFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "SFTP 未连接"
        case .downloadFailed(let error): return "下载失败: \(error.localizedDescription)"
        case .uploadFailed(let error): return "上传失败: \(error.localizedDescription)"
        case .listFailed(let error): return "获取文件列表失败: \(error.localizedDescription)"
        case .deleteFailed(let error): return "删除失败: \(error.localizedDescription)"
        case .createDirectoryFailed(let error): return "创建目录失败: \(error.localizedDescription)"
        }
    }
}

@MainActor
@Observable
final class SFTPService {
    private var client: SFTPClient?
    private var activeTransfers: [UUID: Task<Void, Error>] = [:]

    var isConnected: Bool { client != nil }

    var transferTasks: [TransferTask] = []

    var hasActiveTransfers: Bool {
        transferTasks.contains { !$0.isTerminalStatus }
    }

    func connect(client: SSHClient) async throws {
        let sftpClient = try await client.openSFTP()
        self.client = sftpClient
    }

    func disconnect() async {
        cancelAllTransfers()
        try? await client?.close()
        client = nil
    }

    func dismissCompletedTasks() {
        transferTasks.removeAll { $0.isTerminalStatus }
    }

    func removeTask(_ task: TransferTask) {
        activeTransfers[task.id]?.cancel()
        activeTransfers[task.id] = nil
        transferTasks.removeAll { $0.id == task.id }
    }

    func cancelAllTransfers() {
        activeTransfers.values.forEach { $0.cancel() }
        activeTransfers.removeAll()
        transferTasks.removeAll { !$0.isTerminalStatus }
    }

    func listDirectory(at path: String) async throws -> [SFTPItem] {
        guard let client else { throw SFTPError.notConnected }
        do {
            let listing = try await client.listDirectory(atPath: path)
            let items = listing.flatMap { name in
                name.components
                    .filter { $0.filename != "." && $0.filename != ".." }
                    .map { component -> SFTPItem in
                        let name = component.filename
                        let fullPath = path == "/" ? "/" + name : path + "/" + name
                        let attrs = component.attributes
                        let isDir = (attrs.permissions.map { ($0 & 0o040000) != 0 }) ?? false
                        return SFTPItem(
                            name: name,
                            path: fullPath,
                            isDirectory: isDir,
                            size: attrs.size ?? 0,
                            modificationTime: attrs.accessModificationTime?.modificationTime
                        )
                    }
            }
            return items.sorted {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory && !$1.isDirectory
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch {
            throw SFTPError.listFailed(error)
        }
    }

    func downloadFile(remotePath: String, to localURL: URL) async throws {
        guard let client else { throw SFTPError.notConnected }
        do {
            let tempURL = localURL.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let chunkSize: UInt32 = 64 * 1024
            let file = try await client.openFile(filePath: remotePath, flags: .read)
            defer { Task { try? await file.close() } }

            let attrs = try await file.readAttributes()
            let totalSize = attrs.size ?? 0

            FileManager.default.createFile(atPath: tempURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: tempURL)
            defer { try? handle.close() }

            var offset: UInt64 = 0
            while true {
                try Task.checkCancellation()
                let buffer = try await file.read(from: offset, length: chunkSize)
                let bytesRead = buffer.readableBytes
                guard bytesRead > 0 else { break }
                try handle.write(contentsOf: buffer.readableBytesView)
                offset += UInt64(bytesRead)
            }
            if totalSize == 0 || offset <= totalSize {
                try FileManager.default.removeItem(at: localURL)
                try FileManager.default.moveItem(at: tempURL, to: localURL)
            }
        } catch {
            throw SFTPError.downloadFailed(error)
        }
    }

    func uploadFile(from localURL: URL, to remotePath: String) async throws {
        guard let client else { throw SFTPError.notConnected }
        do {
            let file = try await client.openFile(filePath: remotePath, flags: [.write, .create, .truncate])
            defer { Task { try? await file.close() } }

            let handle = try FileHandle(forReadingFrom: localURL)
            defer { try? handle.close() }

            let chunkSize = 64 * 1024
            var offset: UInt64 = 0

            while true {
                try Task.checkCancellation()
                let data = try handle.read(upToCount: chunkSize) ?? Data()
                guard !data.isEmpty else { break }
                try await file.write(ByteBuffer(bytes: data), at: offset)
                offset += UInt64(data.count)
            }
        } catch {
            throw SFTPError.uploadFailed(error)
        }
    }

    func deleteItem(at path: String) async throws {
        guard let client else { throw SFTPError.notConnected }
        do {
            try await client.remove(at: path)
        } catch {
            do {
                try await client.rmdir(at: path)
            } catch {
                throw SFTPError.deleteFailed(error)
            }
        }
    }

    func createDirectory(at path: String) async throws {
        guard let client else { throw SFTPError.notConnected }
        do {
            try await client.createDirectory(atPath: path)
        } catch {
            throw SFTPError.createDirectoryFailed(error)
        }
    }

    // MARK: - Streaming Transfers

    func downloadFile(remotePath: String, to localURL: URL, task: TransferTask) async throws {
        guard let client else { throw SFTPError.notConnected }

        task.status = .transferring
        let transferID = task.id
        let transfer = Task<Void, Error> {
            let file = try await client.openFile(filePath: remotePath, flags: .read)
            defer { Task { try? await file.close() } }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ShellDeck-\(UUID().uuidString).partial")
            defer { try? FileManager.default.removeItem(at: tempURL) }

            guard FileManager.default.createFile(atPath: tempURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let handle = try FileHandle(forWritingTo: tempURL)
            defer { try? handle.close() }

            let attrs = try await file.readAttributes()
            let totalSize = attrs.size ?? task.totalBytes
            let chunkSize: UInt32 = 64 * 1024
            var offset: UInt64 = 0

            while true {
                try Task.checkCancellation()
                let buffer = try await file.read(from: offset, length: chunkSize)
                let bytesRead = buffer.readableBytes
                guard bytesRead > 0 else { break }
                try handle.write(contentsOf: buffer.readableBytesView)
                offset += UInt64(bytesRead)
                await MainActor.run {
                    task.transferredBytes = offset
                }
            }

            if totalSize == 0 || offset <= totalSize {
                if FileManager.default.fileExists(atPath: localURL.path) {
                    try FileManager.default.removeItem(at: localURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: localURL)
            }
        }

        activeTransfers[transferID] = transfer
        do {
            try await transfer.value
            task.status = .completed
        } catch is CancellationError {
            task.status = .failed("已取消")
            throw CancellationError()
        } catch {
            task.status = .failed(error.localizedDescription)
            throw SFTPError.downloadFailed(error)
        }
        activeTransfers[transferID] = nil
        cleanupCompletedTasksIfNeeded()
    }

    func uploadFile(from localURL: URL, to remotePath: String, task: TransferTask) async throws {
        guard let client else { throw SFTPError.notConnected }

        task.status = .transferring
        let transferID = task.id
        let transfer = Task<Void, Error> {
            let file = try await client.openFile(filePath: remotePath, flags: [.write, .create, .truncate])
            defer { Task { try? await file.close() } }

            let handle = try FileHandle(forReadingFrom: localURL)
            defer { try? handle.close() }

            let totalBytes = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? UInt64) ?? task.totalBytes
            let chunkSize = 64 * 1024
            var offset: UInt64 = 0

            while true {
                try Task.checkCancellation()
                let data = try handle.read(upToCount: chunkSize) ?? Data()
                guard !data.isEmpty else { break }
                try await file.write(ByteBuffer(bytes: data), at: offset)
                offset += UInt64(data.count)
                await MainActor.run {
                    task.transferredBytes = offset
                }
            }

            if totalBytes > 0 {
                await MainActor.run {
                    task.transferredBytes = totalBytes
                }
            }
        }

        activeTransfers[transferID] = transfer
        do {
            try await transfer.value
            task.status = .completed
        } catch is CancellationError {
            task.status = .failed("已取消")
            throw CancellationError()
        } catch {
            task.status = .failed(error.localizedDescription)
            throw SFTPError.uploadFailed(error)
        }
        activeTransfers[transferID] = nil
        cleanupCompletedTasksIfNeeded()
    }

    private func cleanupCompletedTasksIfNeeded() {
        let shouldCleanup = transferTasks.count > 20
        if shouldCleanup {
            transferTasks.removeAll { $0.isTerminalStatus }
        }
    }
}
