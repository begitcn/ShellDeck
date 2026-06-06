import XCTest
@testable import ShellDeck

/// KeychainHelper 测试
///
/// 这些测试直接操作 macOS Keychain，需要在 macOS 上运行。
/// 测试使用随机 key 名以避免与真实数据冲突。
final class KeychainHelperTests: XCTestCase {
    private var testKey: String!

    override func setUp() {
        super.setUp()
        testKey = "ShellDeckTest_\(UUID().uuidString)"
    }

    override func tearDown() {
        KeychainHelper.delete(key: testKey)
        testKey = nil
        super.tearDown()
    }

    // MARK: - 基本读写

    func test_saveThenRead_returnsSameValue() throws {
        let expected = "test-secret-\(UUID().uuidString)"
        try KeychainHelper.save(key: testKey, value: expected)
        let actual = try KeychainHelper.read(key: testKey)
        XCTAssertEqual(actual, expected)
    }

    func test_overwrite_saveThenRead_returnsNewValue() throws {
        try KeychainHelper.save(key: testKey, value: "old-value")
        try KeychainHelper.save(key: testKey, value: "new-value")
        let actual = try KeychainHelper.read(key: testKey)
        XCTAssertEqual(actual, "new-value")
    }

    // MARK: - 读取不存在的 key

    func test_readNonExistentKey_throwsItemNotFound() {
        // testKey 尚未被 save，直接 read
        XCTAssertThrowsError(try KeychainHelper.read(key: testKey)) { error in
            guard let keychainError = error as? KeychainError else {
                XCTFail("应抛出 KeychainError，实际抛出: \(type(of: error))")
                return
            }
            if case .itemNotFound = keychainError {
                // 预期
            } else {
                XCTFail("应抛出 itemNotFound，实际抛出: \(keychainError)")
            }
        }
    }

    // MARK: - 删除后读取

    func test_deleteThenRead_throwsError() throws {
        try KeychainHelper.save(key: testKey, value: "temp-value")
        KeychainHelper.delete(key: testKey)
        XCTAssertThrowsError(try KeychainHelper.read(key: testKey))
    }

    // MARK: - KeychainError errorDescription

    func test_itemNotFound_errorDescription() {
        XCTAssertEqual(
            KeychainError.itemNotFound.errorDescription,
            "Keychain 中未找到该条目"
        )
    }

    func test_duplicateItem_errorDescription() {
        XCTAssertEqual(
            KeychainError.duplicateItem.errorDescription,
            "Keychain 中存在重复条目"
        )
    }

    func test_invalidData_errorDescription() {
        XCTAssertEqual(
            KeychainError.invalidData.errorDescription,
            "Keychain 数据格式无效"
        )
    }

    func test_unexpectedStatus_errorDescription() {
        let expected = "Keychain 操作失败，错误码: -25300"
        XCTAssertEqual(
            KeychainError.unexpectedStatus(-25300).errorDescription,
            expected
        )
    }
}
