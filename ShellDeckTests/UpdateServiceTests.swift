import XCTest
@testable import ShellDeck

/// UpdateService 测试
///
/// isVersion 原为 private，为支持测试已改为 internal（去除 private 关键字）。
/// 通过 @testable import 即可在此访问。
final class UpdateServiceTests: XCTestCase {
    // MARK: - currentVersion

    func test_currentVersion_isNotEmpty() {
        let service = UpdateService.shared
        XCTAssertFalse(service.currentVersion.isEmpty)
    }

    // MARK: - isVersion 比较（精确值）

    func test_isVersion_greater_majorBump() {
        XCTAssertTrue(UpdateService.shared.isVersion("2.0", greaterThan: "1.9.9"))
    }

    func test_isVersion_equal_returnsFalse() {
        XCTAssertFalse(UpdateService.shared.isVersion("1.0.0", greaterThan: "1.0.0"))
    }

    func test_isVersion_greater_midVersion() {
        XCTAssertTrue(UpdateService.shared.isVersion("2.0.0", greaterThan: "1.2.3"))
    }

    func test_isVersion_lesser_returnsFalse() {
        XCTAssertFalse(UpdateService.shared.isVersion("1.0.0", greaterThan: "2.0.0"))
    }

    // MARK: - isVersion 不等长版本号

    func test_isVersion_unequalLength_v1Longer() {
        // "1.2.3.4" > "1.2.3"
        XCTAssertTrue(UpdateService.shared.isVersion("1.2.3.4", greaterThan: "1.2.3"))
    }

    func test_isVersion_unequalLength_v2Longer() {
        // "2.0.1" > "2.0"（不等长，patch 更高）
        XCTAssertTrue(UpdateService.shared.isVersion("2.0.1", greaterThan: "2.0"))
    }

    func test_isVersion_unequalLength_majorDifference() {
        // "3" > "2.9.9.9"
        XCTAssertTrue(UpdateService.shared.isVersion("3", greaterThan: "2.9.9.9"))
    }

    // MARK: - resetStatus

    @MainActor
    func test_resetStatus_setsIdle() {
        let service = UpdateService.shared
        service.resetStatus()
        XCTAssertEqual(service.checkStatus, .idle)
        XCTAssertNil(service.downloadError)
    }
}
