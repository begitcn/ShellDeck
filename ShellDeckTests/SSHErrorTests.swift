import XCTest
@testable import ShellDeck

final class SSHErrorTests: XCTestCase {
    // MARK: - errorDescription 文本内容验证

    func test_keychainItemNotFound_description() {
        XCTAssertEqual(
            SSHError.keychainItemNotFound.errorDescription,
            "未在 Keychain 中找到该服务器的凭证"
        )
    }

    func test_keychainReadFailed_description() {
        let underlying = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "权限被拒绝"])
        let expected = "Keychain 读取失败: 权限被拒绝"
        XCTAssertEqual(SSHError.keychainReadFailed(underlying).errorDescription, expected)
    }

    func test_connectionFailed_description() {
        let underlying = NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "连接超时"])
        let expected = "SSH 连接失败: 连接超时"
        XCTAssertEqual(SSHError.connectionFailed(underlying).errorDescription, expected)
    }

    func test_invalidPrivateKey_description() {
        XCTAssertEqual(SSHError.invalidPrivateKey.errorDescription, "私钥格式无效")
    }

    func test_unsupportedPrivateKeyFormat_description() {
        XCTAssertEqual(
            SSHError.unsupportedPrivateKeyFormat.errorDescription,
            "不支持的私钥格式或密码短语错误"
        )
    }

    func test_encryptedKeyNeedsPassphrase_description() {
        XCTAssertEqual(
            SSHError.encryptedKeyNeedsPassphrase.errorDescription,
            "该私钥已加密，请在编辑服务器时填写「私钥密码」"
        )
    }

    func test_notConnected_description() {
        XCTAssertEqual(SSHError.notConnected.errorDescription, "尚未连接到服务器")
    }

    // MARK: - Equatable

    func test_equatable_sameCase_areEqual() {
        XCTAssertEqual(SSHError.keychainItemNotFound, SSHError.keychainItemNotFound)
        XCTAssertEqual(SSHError.invalidPrivateKey, SSHError.invalidPrivateKey)
        XCTAssertEqual(SSHError.unsupportedPrivateKeyFormat, SSHError.unsupportedPrivateKeyFormat)
        XCTAssertEqual(SSHError.encryptedKeyNeedsPassphrase, SSHError.encryptedKeyNeedsPassphrase)
        XCTAssertEqual(SSHError.notConnected, SSHError.notConnected)

        let err1 = SSHError.connectionFailed(NSError(domain: "a", code: 1))
        let err2 = SSHError.connectionFailed(NSError(domain: "b", code: 2))
        XCTAssertEqual(err1, err2, "connectionFailed 忽略关联错误值")

        let kerr1 = SSHError.keychainReadFailed(NSError(domain: "a", code: 1))
        let kerr2 = SSHError.keychainReadFailed(NSError(domain: "b", code: 2))
        XCTAssertEqual(kerr1, kerr2, "keychainReadFailed 忽略关联错误值")
    }

    func test_equatable_differentCases_areNotEqual() {
        XCTAssertNotEqual(SSHError.keychainItemNotFound, SSHError.notConnected)
        XCTAssertNotEqual(SSHError.invalidPrivateKey, SSHError.unsupportedPrivateKeyFormat)
        XCTAssertNotEqual(SSHError.encryptedKeyNeedsPassphrase, SSHError.connectionFailed(NSError(domain: "x", code: 0)))
        XCTAssertNotEqual(SSHError.notConnected, SSHError.keychainReadFailed(NSError(domain: "x", code: 0)))
    }
}
