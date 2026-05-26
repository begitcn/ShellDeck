import Foundation
import SwiftData
import SSHClient
import NIOSSH
import NIOCore
import CryptoKit

enum SSHError: LocalizedError, Equatable {
    case keychainItemNotFound
    case keychainReadFailed(Error)
    case connectionFailed(Error)
    case invalidPrivateKey
    case unsupportedPrivateKeyFormat
    case notConnected
    case shellCreationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .keychainItemNotFound: "未在 Keychain 中找到该服务器的凭证"
        case .keychainReadFailed(let error): "Keychain 读取失败: \(error.localizedDescription)"
        case .connectionFailed(let error): "SSH 连接失败: \(error.localizedDescription)"
        case .invalidPrivateKey: "私钥格式无效"
        case .unsupportedPrivateKeyFormat: "不支持的私钥格式（支持 Ed25519、P256、P384、P521 PKCS#8）"
        case .notConnected: "尚未连接到服务器"
        case .shellCreationFailed(let error): "创建 Shell 通道失败: \(error.localizedDescription)"
        }
    }

    static func == (lhs: SSHError, rhs: SSHError) -> Bool {
        switch (lhs, rhs) {
        case (.keychainItemNotFound, .keychainItemNotFound): true
        case (.keychainReadFailed, .keychainReadFailed): true
        case (.connectionFailed, .connectionFailed): true
        case (.invalidPrivateKey, .invalidPrivateKey): true
        case (.unsupportedPrivateKeyFormat, .unsupportedPrivateKeyFormat): true
        case (.notConnected, .notConnected): true
        case (.shellCreationFailed, .shellCreationFailed): true
        default: false
        }
    }
}

@MainActor
@Observable
final class SSHService {
    enum ConnectionState {
        case disconnected
        case connecting
        case connected(host: String)
        case failed(Error)
    }

    private(set) var state: ConnectionState = .disconnected
    private var connection: SSHConnection?

    func connect(to server: Server) async {
        state = .connecting

        do {
            let auth = try makeAuthentication(for: server)
            let sshConnection = SSHConnection(
                host: server.host,
                port: UInt16(server.port),
                authentication: auth
            )
            try await sshConnection.start()
            self.connection = sshConnection
            state = .connected(host: server.host)
        } catch let error as SSHError {
            state = .failed(error)
        } catch {
            state = .failed(SSHError.connectionFailed(error))
        }
    }

    func disconnect() async {
        await connection?.cancel()
        connection = nil
        state = .disconnected
    }

    func requestShell() async throws -> SSHShell {
        guard let connection else {
            throw SSHError.notConnected
        }
        do {
            return try await connection.requestShell()
        } catch {
            throw SSHError.shellCreationFailed(error)
        }
    }

    // MARK: - Private

    private func makeAuthentication(for server: Server) throws -> SSHAuthentication {
        switch server.authTypeEnum {
        case .password:
            let password: String
            do {
                password = try KeychainHelper.read(key: server.id.uuidString)
            } catch KeychainError.itemNotFound {
                throw SSHError.keychainItemNotFound
            } catch {
                throw SSHError.keychainReadFailed(error)
            }
            return SSHAuthentication(
                username: server.username,
                method: .password(.init(password)),
                hostKeyValidation: .acceptAll()
            )

        case .privateKey:
            let privateKeyPEM: String
            do {
                privateKeyPEM = try KeychainHelper.read(key: server.id.uuidString + ".key")
            } catch KeychainError.itemNotFound {
                throw SSHError.keychainItemNotFound
            } catch {
                throw SSHError.keychainReadFailed(error)
            }
            let delegate = try PrivateKeyAuthDelegate(
                username: server.username,
                privateKeyPEM: privateKeyPEM
            )
            return SSHAuthentication(
                username: server.username,
                method: .custom(delegate),
                hostKeyValidation: .acceptAll()
            )
        }
    }
}

// MARK: - Private Key Authentication Delegate

final class PrivateKeyAuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let privateKey: NIOSSHPrivateKey

    init(username: String, privateKeyPEM: String) throws {
        self.username = username
        self.privateKey = try Self.parsePrivateKey(pem: privateKeyPEM)
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard availableMethods.contains(.publicKey) else {
            nextChallengePromise.fail(SSHError.unsupportedPrivateKeyFormat)
            return
        }
        let offer = NIOSSHUserAuthenticationOffer(
            username: username,
            serviceName: "",
            offer: .privateKey(.init(privateKey: privateKey))
        )
        nextChallengePromise.succeed(offer)
    }

    // MARK: - PEM Parsing

    private static func parsePrivateKey(pem: String) throws -> NIOSSHPrivateKey {
        if let p256 = try? P256.Signing.PrivateKey(pemRepresentation: pem) {
            return NIOSSHPrivateKey(p256Key: p256)
        }
        if let p384 = try? P384.Signing.PrivateKey(pemRepresentation: pem) {
            return NIOSSHPrivateKey(p384Key: p384)
        }
        if let p521 = try? P521.Signing.PrivateKey(pemRepresentation: pem) {
            return NIOSSHPrivateKey(p521Key: p521)
        }
        if let ed25519 = try? parseEd25519PKCS8(pem: pem) {
            return NIOSSHPrivateKey(ed25519Key: ed25519)
        }
        throw SSHError.unsupportedPrivateKeyFormat
    }

    private static func parseEd25519PKCS8(pem: String) throws -> Curve25519.Signing.PrivateKey {
        let lines = pem.split(whereSeparator: \.isNewline)
        guard lines.count >= 3,
              let first = lines.first, first.hasPrefix("-----BEGIN"),
              let last = lines.last, last.hasPrefix("-----END")
        else {
            throw SSHError.invalidPrivateKey
        }
        let base64 = lines.dropFirst().dropLast().joined()
        guard let der = Data(base64Encoded: base64) else {
            throw SSHError.invalidPrivateKey
        }
        // PKCS#8 DER for Ed25519:
        // SEQUENCE { INTEGER 0, SEQUENCE { OID(1.3.101.112) }, OCTET STRING { OCTET STRING (32 bytes) } }
        var offset = 0
        func skipTag(_ expected: UInt8) throws {
            guard offset < der.count, der[offset] == expected else { throw SSHError.invalidPrivateKey }
            offset += 1
            let len = try decodeLength()
            offset += len
        }
        func decodeLength() throws -> Int {
            guard offset < der.count else { throw SSHError.invalidPrivateKey }
            let first = der[offset]
            offset += 1
            if first < 0x80 { return Int(first) }
            let count = Int(first & 0x7F)
            guard offset + count <= der.count else { throw SSHError.invalidPrivateKey }
            let length = try (0..<count).reduce(0) { acc, _ in
                (acc << 8) | Int(der[offset]); offset += 1; return acc
            }
            return length
        }
        func readTag(_ expected: UInt8) throws -> Data {
            guard offset < der.count, der[offset] == expected else { throw SSHError.invalidPrivateKey }
            offset += 1
            let len = try decodeLength()
            guard offset + len <= der.count else { throw SSHError.invalidPrivateKey }
            let value = der[offset..<offset + len]
            offset += len
            return Data(value)
        }
        // Skip outer SEQUENCE
        offset = 0
        _ = try readTag(0x30)
        // Skip version INTEGER == 0
        try skipTag(0x02)
        // Skip algorithm SEQUENCE (contains OID)
        try skipTag(0x30)
        // Read outer OCTET STRING wrapping the key
        let outerOctet = try readTag(0x04)
        // Parse inner OCTET STRING from outerOctet
        var inner = 0
        func readInner(offset: inout Int) throws -> Data {
            guard inner < outerOctet.count, outerOctet[inner] == 0x04 else { throw SSHError.invalidPrivateKey }
            inner += 1
            let len: Int
            let first = outerOctet[inner]; inner += 1
            if first < 0x80 {
                len = Int(first)
            } else {
                let count = Int(first & 0x7F)
                len = try (0..<count).reduce(0) { acc, _ in
                    (acc << 8) | Int(outerOctet[inner]); inner += 1; return acc
                }
            }
            guard inner + len <= outerOctet.count else { throw SSHError.invalidPrivateKey }
            return outerOctet[inner..<inner + len]
        }
        let keyData = try readInner(offset: &inner)
        return try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
    }
}
