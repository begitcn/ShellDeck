import Foundation
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

    var isConnected: Bool { client != nil }

    func connect(client: SSHClient) async throws {
        let sftpClient = try await client.openSFTP()
        self.client = sftpClient
    }

    func disconnect() async {
        try? await client?.close()
        client = nil
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
            let data = try await client.withFile(filePath: remotePath, flags: .read) { file in
                try await file.readAll()
            }
            try Data(data.readableBytesView).write(to: localURL)
        } catch {
            throw SFTPError.downloadFailed(error)
        }
    }

    func uploadFile(from localURL: URL, to remotePath: String) async throws {
        guard let client else { throw SFTPError.notConnected }
        let data: Data
        do {
            data = try Data(contentsOf: localURL)
        } catch {
            throw SFTPError.uploadFailed(error)
        }
        do {
            _ = try await client.withFile(filePath: remotePath, flags: [.write, .create, .truncate]) { file in
                var buffer = ByteBuffer()
                buffer.writeBytes(data)
                try await file.write(buffer)
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
}
