import Foundation
import SSHClient

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

    func connect(connection: SSHConnection) async throws {
        let sftpClient = try await connection.requestSFTPClient()
        self.client = sftpClient
    }

    func disconnect() async {
        await client?.close()
        client = nil
    }

    func listDirectory(at path: String) async throws -> [SFTPItem] {
        guard let client else { throw SFTPError.notConnected }
        do {
            let components = try await client.listDirectory(at: SFTPFilePath(path))
            let items = components
                .filter { component in
                    let name = component.filename.string
                    return name != "." && name != ".."
                }
                .map { component -> SFTPItem in
                    let name = component.filename.string
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

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resultSent = false
            let sendResult: (Result<Void, Error>) -> Void = { result in
                guard !resultSent else { return }
                resultSent = true
                continuation.resume(with: result)
            }

            client.withFile(at: SFTPFilePath(remotePath), flags: [.read]) { file, done in
                var allData = Data()
                var offset: UInt64 = 0
                let chunkSize: UInt32 = 32768

                func readChunk() {
                    file.read(from: offset, length: chunkSize) { result in
                        switch result {
                        case .success(let data):
                            if data.isEmpty {
                                do {
                                    try allData.write(to: localURL, options: .atomic)
                                } catch {
                                    sendResult(.failure(SFTPError.downloadFailed(error)))
                                    done()
                                    return
                                }
                                sendResult(.success(()))
                                done()
                            } else {
                                allData.append(data)
                                offset += UInt64(data.count)
                                readChunk()
                            }
                        case .failure(let error):
                            sendResult(.failure(SFTPError.downloadFailed(error)))
                            done()
                        }
                    }
                }

                readChunk()
            } completion: { result in
                if case .failure(let error) = result {
                    sendResult(.failure(SFTPError.downloadFailed(error)))
                }
            }
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

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resultSent = false
            let sendResult: (Result<Void, Error>) -> Void = { result in
                guard !resultSent else { return }
                resultSent = true
                continuation.resume(with: result)
            }

            client.withFile(at: SFTPFilePath(remotePath), flags: [.write, .create, .truncate]) { file, done in
                file.write(data, at: 0) { result in
                    switch result {
                    case .success:
                        sendResult(.success(()))
                        done()
                    case .failure(let error):
                        sendResult(.failure(SFTPError.uploadFailed(error)))
                        done()
                    }
                }
            } completion: { result in
                if case .failure(let error) = result {
                    sendResult(.failure(SFTPError.uploadFailed(error)))
                }
            }
        }
    }

    func deleteItem(at path: String) async throws {
        guard let client else { throw SFTPError.notConnected }
        do {
            try await client.removeFile(at: SFTPFilePath(path))
        } catch {
            do {
                try await client.removeDirectory(at: SFTPFilePath(path))
            } catch {
                throw SFTPError.deleteFailed(error)
            }
        }
    }

    func createDirectory(at path: String) async throws {
        guard let client else { throw SFTPError.notConnected }
        do {
            try await client.createDirectory(at: SFTPFilePath(path))
        } catch {
            throw SFTPError.createDirectoryFailed(error)
        }
    }
}
