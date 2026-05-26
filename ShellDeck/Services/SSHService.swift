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
        case .unsupportedPrivateKeyFormat: "不支持的私钥格式\n\n检测到 RSA 密钥，但 ShellDeck 使用的 SSH 库不支持 RSA 算法。\n请使用 Ed25519 或 ECDSA 密钥：\n  ssh-keygen -t ed25519"
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
    private(set) var connection: SSHConnection?

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
            let passphrase = try? KeychainHelper.read(key: server.id.uuidString + ".passphrase")
            let delegate = try PrivateKeyAuthDelegate(
                username: server.username,
                privateKeyPEM: privateKeyPEM,
                passphrase: passphrase
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

    init(username: String, privateKeyPEM: String, passphrase: String? = nil) throws {
        self.username = username
        self.privateKey = try Self.parsePrivateKey(pem: privateKeyPEM, passphrase: passphrase)
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

    private static func parsePrivateKey(pem: String, passphrase: String?) throws -> NIOSSHPrivateKey {
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains("-----BEGIN OPENSSH PRIVATE KEY") {
            return try parseOpenSSH(pem: trimmed, passphrase: passphrase)
        }
        if trimmed.contains("-----BEGIN EC PRIVATE KEY") {
            return try parseSEC1(pem: trimmed)
        }
        if trimmed.contains("-----BEGIN RSA PRIVATE KEY") {
            throw SSHError.unsupportedPrivateKeyFormat
        }

        // PKCS#8
        return try parsePKCS8(pem: trimmed)
    }

    private static func parsePKCS8(pem: String) throws -> NIOSSHPrivateKey {
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

    // MARK: - OpenSSH Format

    private static func parseOpenSSH(pem: String, passphrase: String?) throws -> NIOSSHPrivateKey {
        let lines = pem.split(whereSeparator: \.isNewline)
        guard lines.count >= 3,
              let first = lines.first, first.trimmingCharacters(in: .whitespaces).hasPrefix("-----BEGIN OPENSSH PRIVATE KEY"),
              let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("-----END OPENSSH PRIVATE KEY")
        else {
            throw SSHError.invalidPrivateKey
        }
        let base64 = lines.dropFirst().dropLast().joined()
        guard let der = Data(base64Encoded: base64) else {
            throw SSHError.invalidPrivateKey
        }

        var offset = 0

        func readU32() throws -> UInt32 {
            guard offset + 4 <= der.count else { throw SSHError.invalidPrivateKey }
            let val = UInt32(der[offset]) << 24 | UInt32(der[offset+1]) << 16 | UInt32(der[offset+2]) << 8 | UInt32(der[offset+3])
            offset += 4
            return val
        }

        func readString() throws -> Data {
            let len = try readU32()
            guard offset + Int(len) <= der.count else { throw SSHError.invalidPrivateKey }
            let val = der[offset..<offset+Int(len)]
            offset += Int(len)
            return val
        }

        let magic = "openssh-key-v1"
        guard der.count >= magic.count + 1,
              String(decoding: der[0..<magic.count], as: UTF8.self) == magic,
              der[magic.count] == 0
        else {
            throw SSHError.invalidPrivateKey
        }
        offset = magic.count + 1

        let ciphername = String(decoding: try readString(), as: UTF8.self)
        let kdfname = String(decoding: try readString(), as: UTF8.self)
        _ = try readString()
        let numKeys = try readU32()

        for _ in 0..<numKeys {
            _ = try readString()
        }

        let encryptedSection = try readString()

        guard ciphername == "none", kdfname == "none" else {
            throw SSHError.unsupportedPrivateKeyFormat
        }

        let privateSection = encryptedSection
        var pos = 0

        func readU32ps() throws -> UInt32 {
            guard pos + 4 <= privateSection.count else { throw SSHError.invalidPrivateKey }
            let val = UInt32(privateSection[pos]) << 24 | UInt32(privateSection[pos+1]) << 16 | UInt32(privateSection[pos+2]) << 8 | UInt32(privateSection[pos+3])
            pos += 4
            return val
        }

        func readStringps() throws -> Data {
            let len = try readU32ps()
            guard pos + Int(len) <= privateSection.count else { throw SSHError.invalidPrivateKey }
            let val = privateSection[pos..<pos+Int(len)]
            pos += Int(len)
            return val
        }

        let check1 = try readU32ps()
        let check2 = try readU32ps()
        guard check1 == check2 else { throw SSHError.invalidPrivateKey }

        let keyType = String(decoding: try readStringps(), as: UTF8.self)

        switch keyType {
        case "ssh-ed25519":
            _ = try readStringps()
            let privateKeyData = try readStringps()
            guard privateKeyData.count >= 32 else { throw SSHError.invalidPrivateKey }
            let seed = privateKeyData[0..<32]
            return NIOSSHPrivateKey(ed25519Key: try Curve25519.Signing.PrivateKey(rawRepresentation: seed))

        case "ecdsa-sha2-nistp256":
            _ = try readStringps()
            _ = try readStringps()
            let privateKeyData = try readStringps()
            guard privateKeyData.count == 32 else { throw SSHError.invalidPrivateKey }
            return NIOSSHPrivateKey(p256Key: try P256.Signing.PrivateKey(rawRepresentation: privateKeyData))

        case "ecdsa-sha2-nistp384":
            _ = try readStringps()
            _ = try readStringps()
            let privateKeyData = try readStringps()
            guard privateKeyData.count == 48 else { throw SSHError.invalidPrivateKey }
            return NIOSSHPrivateKey(p384Key: try P384.Signing.PrivateKey(rawRepresentation: privateKeyData))

        case "ecdsa-sha2-nistp521":
            _ = try readStringps()
            _ = try readStringps()
            let privateKeyData = try readStringps()
            guard privateKeyData.count == 66 else { throw SSHError.invalidPrivateKey }
            return NIOSSHPrivateKey(p521Key: try P521.Signing.PrivateKey(rawRepresentation: privateKeyData))

        default:
            throw SSHError.unsupportedPrivateKeyFormat
        }
    }

    // MARK: - SEC1 EC Private Key

    private static func parseSEC1(pem: String) throws -> NIOSSHPrivateKey {
        let lines = pem.split(whereSeparator: \.isNewline)
        guard lines.count >= 3,
              let first = lines.first, first.hasPrefix("-----BEGIN EC PRIVATE KEY"),
              let last = lines.last, last.hasPrefix("-----END EC PRIVATE KEY")
        else {
            throw SSHError.invalidPrivateKey
        }
        let base64 = lines.dropFirst().dropLast().joined()
        guard let der = Data(base64Encoded: base64) else {
            throw SSHError.invalidPrivateKey
        }

        var offset = 0

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

        func readAnyTag() throws -> (tag: UInt8, value: Data) {
            guard offset < der.count else { throw SSHError.invalidPrivateKey }
            let tag = der[offset]
            offset += 1
            let len = try decodeLength()
            guard offset + len <= der.count else { throw SSHError.invalidPrivateKey }
            let value = der[offset..<offset + len]
            offset += len
            return (tag, Data(value))
        }

        _ = try readTag(0x30)
        _ = try readTag(0x02)
        let privateKeyBytes = try readTag(0x04)

        var curveOID: Data?
        while offset < der.count {
            let (tag, value) = try readAnyTag()
            if tag == 0xA0 {
                var oidOff = 0
                let contents = value
                if oidOff < contents.count && contents[oidOff] == 0x06 {
                    oidOff += 1
                    let oidLen: Int
                    let first = contents[oidOff]; oidOff += 1
                    if first < 0x80 {
                        oidLen = Int(first)
                    } else {
                        let count = Int(first & 0x7F)
                        guard oidOff + count <= contents.count else { break }
                        var len = 0
                        for _ in 0..<count {
                            len = (len << 8) | Int(contents[oidOff]); oidOff += 1
                        }
                        oidLen = len
                    }
                    guard oidOff + oidLen <= contents.count else { break }
                    curveOID = contents[oidOff..<oidOff + oidLen]
                    break
                }
            }
        }

        guard let oid = curveOID else {
            throw SSHError.unsupportedPrivateKeyFormat
        }

        let p256OID = Data([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07])
        let p384OID = Data([0x2B, 0x81, 0x04, 0x00, 0x22])
        let p521OID = Data([0x2B, 0x81, 0x04, 0x00, 0x23])

        if oid == p256OID {
            guard privateKeyBytes.count == 32 else { throw SSHError.invalidPrivateKey }
            return NIOSSHPrivateKey(p256Key: try P256.Signing.PrivateKey(rawRepresentation: privateKeyBytes))
        } else if oid == p384OID {
            guard privateKeyBytes.count == 48 else { throw SSHError.invalidPrivateKey }
            return NIOSSHPrivateKey(p384Key: try P384.Signing.PrivateKey(rawRepresentation: privateKeyBytes))
        } else if oid == p521OID {
            guard privateKeyBytes.count == 66 else { throw SSHError.invalidPrivateKey }
            return NIOSSHPrivateKey(p521Key: try P521.Signing.PrivateKey(rawRepresentation: privateKeyBytes))
        }

        throw SSHError.unsupportedPrivateKeyFormat
    }

    // MARK: - Ed25519 PKCS#8 DER

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
        offset = 0
        _ = try readTag(0x30)
        try skipTag(0x02)
        try skipTag(0x30)
        let outerOctet = try readTag(0x04)
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
