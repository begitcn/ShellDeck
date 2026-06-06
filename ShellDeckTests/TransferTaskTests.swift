import XCTest
@testable import ShellDeck

final class TransferTaskTests: XCTestCase {
    // MARK: - progress 计算

    @MainActor
    func test_progress_totalBytesZero_returnsZero() {
        let task = TransferTask(fileName: "test.txt", type: .upload, totalBytes: 0)
        task.transferredBytes = 100
        XCTAssertEqual(task.progress, 0.0, "totalBytes=0 时 progress 应返回 0")
    }

    @MainActor
    func test_progress_midValue() {
        let task = TransferTask(fileName: "test.txt", type: .download, totalBytes: 1000)
        task.transferredBytes = 500
        XCTAssertEqual(task.progress, 0.5, accuracy: 0.001)
    }

    @MainActor
    func test_progress_fullValue() {
        let task = TransferTask(fileName: "test.txt", type: .upload, totalBytes: 1000)
        task.transferredBytes = 1000
        XCTAssertEqual(task.progress, 1.0, accuracy: 0.001)
    }

    @MainActor
    func test_progress_exceedsTotal_capsAtOne() {
        let task = TransferTask(fileName: "test.txt", type: .upload, totalBytes: 100)
        task.transferredBytes = 200
        XCTAssertEqual(task.progress, 1.0, accuracy: 0.001, "progress 不应超过 1.0")
    }

    // MARK: - speed 计算

    @MainActor
    func test_speed_zeroTransferred_returnsZero() {
        let task = TransferTask(fileName: "test.txt", type: .download, totalBytes: 1000)
        task.transferredBytes = 0
        // 短暂的延时确保 elapsed > 0
        let speed = task.speed
        XCTAssertEqual(speed, 0.0, "transferredBytes=0 时 speed 应为 0")
    }

    // MARK: - speedFormatted

    @MainActor
    func test_speedFormatted_nonEmpty() {
        let task = TransferTask(fileName: "test.txt", type: .upload, totalBytes: 1000)
        XCTAssertFalse(task.speedFormatted.isEmpty)
    }

    @MainActor
    func test_speedFormatted_bytesPerSec() {
        let task = TransferTask(fileName: "test.txt", type: .upload, totalBytes: 1000)
        task.transferredBytes = 500
        // speed 依赖于实际时间流逝，仅验证格式非空
        let formatted = task.speedFormatted
        XCTAssertFalse(formatted.isEmpty)
        // 应该包含 "B/s", "KB/s" 或 "MB/s" 之一
        let containsUnit = formatted.contains("B/s") || formatted.contains("KB/s") || formatted.contains("MB/s")
        XCTAssertTrue(containsUnit, "speedFormatted 应包含速率单位: \(formatted)")
    }

    // MARK: - progressFormatted

    @MainActor
    func test_progressFormatted_nonEmpty() {
        let task = TransferTask(fileName: "test.txt", type: .download, totalBytes: 100)
        XCTAssertFalse(task.progressFormatted.isEmpty)
    }

    @MainActor
    func test_progressFormatted_containsPercent() {
        let task = TransferTask(fileName: "test.txt", type: .upload, totalBytes: 100)
        task.transferredBytes = 50
        XCTAssertTrue(task.progressFormatted.hasSuffix("%"))
    }

    // MARK: - isTerminalStatus

    @MainActor
    func test_isTerminalStatus_pending_false() {
        let task = TransferTask(fileName: "test.txt", type: .upload, totalBytes: 100)
        task.status = .pending
        XCTAssertFalse(task.isTerminalStatus)
    }

    @MainActor
    func test_isTerminalStatus_transferring_false() {
        let task = TransferTask(fileName: "test.txt", type: .upload, totalBytes: 100)
        task.status = .transferring
        XCTAssertFalse(task.isTerminalStatus)
    }

    @MainActor
    func test_isTerminalStatus_completed_true() {
        let task = TransferTask(fileName: "test.txt", type: .upload, totalBytes: 100)
        task.status = .completed
        XCTAssertTrue(task.isTerminalStatus)
    }

    @MainActor
    func test_isTerminalStatus_failed_true() {
        let task = TransferTask(fileName: "test.txt", type: .upload, totalBytes: 100)
        task.status = .failed("Connection lost")
        XCTAssertTrue(task.isTerminalStatus)
    }
}
