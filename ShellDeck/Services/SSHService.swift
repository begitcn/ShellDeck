import Foundation
import Citadel
import CryptoKit
import CCryptoBoringSSL

enum SSHError: LocalizedError, Equatable {
    case keychainItemNotFound
    case keychainReadFailed(Error)
    case connectionFailed(Error)
    case invalidPrivateKey
    case unsupportedPrivateKeyFormat
    case notConnected

    var errorDescription: String? {
        switch self {
        case .keychainItemNotFound: "未在 Keychain 中找到该服务器的凭证"
        case .keychainReadFailed(let error): "Keychain 读取失败: \(error.localizedDescription)"
        case .connectionFailed(let error): "SSH 连接失败: \(error.localizedDescription)"
        case .invalidPrivateKey: "私钥格式无效"
        case .unsupportedPrivateKeyFormat: "不支持的私钥格式"
        case .notConnected: "尚未连接到服务器"
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
        default: false
        }
    }
}

enum SSHService {
    static func connect(to server: Server) async throws -> SSHClient {
        let authMethod = try makeAuthenticationMethod(for: server)
        return try await SSHClient.connect(to: SSHClientSettings(
            host: server.host,
            port: server.port,
            authenticationMethod: { authMethod },
            hostKeyValidator: .acceptAnything()
        ))
    }

    static func disconnect(_ client: SSHClient?) async {
        try? await client?.close()
    }

    // MARK: - Authentication

    private static func makeAuthenticationMethod(for server: Server) throws -> SSHAuthenticationMethod {
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
            return .passwordBased(username: server.username, password: password)

        case .privateKey:
            let privateKeyPEM: String
            do {
                privateKeyPEM = try KeychainHelper.read(key: server.id.uuidString + ".key")
            } catch KeychainError.itemNotFound {
                throw SSHError.keychainItemNotFound
            } catch {
                throw SSHError.keychainReadFailed(error)
            }
            return try parseKey(pem: privateKeyPEM, username: server.username)
        }
    }

    private static func parseKey(pem: String, username: String) throws -> SSHAuthenticationMethod {
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains("-----BEGIN OPENSSH PRIVATE KEY") {
            return try parseOpenSSHKey(pem: trimmed, username: username)
        }

        if trimmed.contains("-----BEGIN RSA PRIVATE KEY") {
            let rsaKey = try parseRSAKey(pem: trimmed)
            return .rsa(username: username, privateKey: rsaKey)
        }

        if trimmed.contains("-----BEGIN EC PRIVATE KEY") {
            if let key = try? parseSEC1Ed25519(pem: trimmed) {
                return .ed25519(username: username, privateKey: key)
            }
        }

        if let edKey = try? parseEd25519PKCS8(pem: trimmed) {
            return .ed25519(username: username, privateKey: edKey)
        }
        if let p256Key = try? P256.Signing.PrivateKey(pemRepresentation: trimmed) {
            return .p256(username: username, privateKey: p256Key)
        }
        if let p384Key = try? P384.Signing.PrivateKey(pemRepresentation: trimmed) {
            return .p384(username: username, privateKey: p384Key)
        }
        if let p521Key = try? P521.Signing.PrivateKey(pemRepresentation: trimmed) {
            return .p521(username: username, privateKey: p521Key)
        }

        throw SSHError.unsupportedPrivateKeyFormat
    }

    // MARK: - OpenSSH Format

    private static func parseOpenSSHKey(pem: String, username: String) throws -> SSHAuthenticationMethod {
        let key = try parseOpenSSHEd25519(pem: pem)
        return .ed25519(username: username, privateKey: key)
    }

    private struct OpenSSHReader {
        let data: Data
        var offset: Int

        init(data: Data) {
            self.data = data
            self.offset = 0
        }

        mutating func readU32() throws -> UInt32 {
            guard offset + 4 <= data.count else { throw SSHError.invalidPrivateKey }
            let val = UInt32(data[offset]) << 24 | UInt32(data[offset+1]) << 16 | UInt32(data[offset+2]) << 8 | UInt32(data[offset+3])
            offset += 4
            return val
        }

        mutating func readString() throws -> Data {
            let len = try readU32()
            guard offset + Int(len) <= data.count else { throw SSHError.invalidPrivateKey }
            let val = data.subdata(in: offset..<offset+Int(len))
            offset += Int(len)
            return val
        }
    }

    // MARK: - OpenSSH Format

    private static func parseOpenSSHEd25519(pem: String) throws -> Curve25519.Signing.PrivateKey {
        let lines = pem.split(whereSeparator: \.isNewline)
        guard lines.count >= 3 else { throw SSHError.invalidPrivateKey }
        let base64 = lines.dropFirst().dropLast().joined()
        guard let der = Data(base64Encoded: base64) else { throw SSHError.invalidPrivateKey }

        var reader = OpenSSHReader(data: der)

        let magic = "openssh-key-v1"
        guard der.count >= magic.count + 1,
              String(decoding: der[0..<magic.count], as: UTF8.self) == magic,
              der[magic.count] == 0
        else { throw SSHError.invalidPrivateKey }
        reader.offset = magic.count + 1

        let ciphername = String(decoding: try reader.readString(), as: UTF8.self)
        let kdfname = String(decoding: try reader.readString(), as: UTF8.self)
        _ = try reader.readString()
        let numKeys = try reader.readU32()
        for _ in 0..<numKeys { _ = try reader.readString() }
        let encSection = try reader.readString()
        guard ciphername == "none", kdfname == "none" else { throw SSHError.unsupportedPrivateKeyFormat }

        var pr = OpenSSHReader(data: encSection)

        let check1 = try pr.readU32()
        let check2 = try pr.readU32()
        guard check1 == check2 else { throw SSHError.invalidPrivateKey }

        let keyType = String(decoding: try pr.readString(), as: UTF8.self)

        switch keyType {
        case "ssh-ed25519":
            _ = try pr.readString()
            let privData = try pr.readString()
            guard privData.count >= 32 else { throw SSHError.invalidPrivateKey }
            return try Curve25519.Signing.PrivateKey(rawRepresentation: privData[0..<32])
        default:
            throw SSHError.unsupportedPrivateKeyFormat
        }
    }

    // MARK: - RSA (via BoringSSL)

    private static func parseRSAKey(pem: String) throws -> Insecure.RSA.PrivateKey {
        let cString = (pem as NSString).utf8String
        guard let cString = cString else { throw SSHError.invalidPrivateKey }

        let bio = CCryptoBoringSSL_BIO_new_mem_buf(cString, -1)
        defer { CCryptoBoringSSL_BIO_free(bio) }
        guard let bio = bio else { throw SSHError.invalidPrivateKey }

        let rsa = CCryptoBoringSSL_PEM_read_bio_RSAPrivateKey(bio, nil, nil, nil)
        defer { if let rsa = rsa { CCryptoBoringSSL_RSA_free(rsa) } }
        guard let rsa = rsa else { throw SSHError.invalidPrivateKey }

        guard let n = CCryptoBoringSSL_BN_dup(CCryptoBoringSSL_RSA_get0_n(rsa)),
              let e = CCryptoBoringSSL_BN_dup(CCryptoBoringSSL_RSA_get0_e(rsa)),
              let d = CCryptoBoringSSL_BN_dup(CCryptoBoringSSL_RSA_get0_d(rsa))
        else { throw SSHError.invalidPrivateKey }

        return Insecure.RSA.PrivateKey(
            privateExponent: d,
            publicExponent: e,
            modulus: n
        )
    }

    // MARK: - Ed25519 PKCS#8

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

    // MARK: - SEC1 Ed25519

    private static func parseSEC1Ed25519(pem: String) throws -> Curve25519.Signing.PrivateKey {
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
            let first = der[offset]; offset += 1
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
            let tag = der[offset]; offset += 1
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

        let ed25519OID = Data([0x2B, 0x65, 0x70])
        guard curveOID == ed25519OID, privateKeyBytes.count == 32 else {
            throw SSHError.unsupportedPrivateKeyFormat
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyBytes)
    }
}
