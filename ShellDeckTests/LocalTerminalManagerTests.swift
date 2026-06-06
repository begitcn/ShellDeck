import XCTest
@testable import ShellDeck

/// LocalTerminalManager 测试
///
/// 所有测试需在主 actor 上运行（项目配置 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor）
final class LocalTerminalManagerTests: XCTestCase {
    @MainActor
    func test_createSession_increasesCount() {
        let manager = LocalTerminalManager()
        XCTAssertEqual(manager.sessions.count, 0)

        manager.createSession()
        XCTAssertEqual(manager.sessions.count, 1)
    }

    @MainActor
    func test_createSession_setsActiveSessionID() {
        let manager = LocalTerminalManager()
        manager.createSession()
        XCTAssertNotNil(manager.activeSessionID)
        XCTAssertEqual(manager.activeSession?.id, manager.activeSessionID)
    }

    // MARK: - closeSession

    @MainActor
    func test_closeSession_removesFromSessions() {
        let manager = LocalTerminalManager()
        manager.createSession()
        let sessionID = manager.activeSessionID!

        manager.closeSession(id: sessionID)
        XCTAssertTrue(manager.sessions.isEmpty)
    }

    @MainActor
    func test_closeSession_clearsActiveSession() {
        let manager = LocalTerminalManager()
        manager.createSession()
        let sessionID = manager.activeSessionID!

        manager.closeSession(id: sessionID)
        XCTAssertNil(manager.activeSession)
        XCTAssertNil(manager.activeSessionID)
    }

    // MARK: - activeSession

    @MainActor
    func test_activeSession_noSession_returnsNil() {
        let manager = LocalTerminalManager()
        XCTAssertNil(manager.activeSession)
    }

    @MainActor
    func test_activeSession_withSession_returnsIt() {
        let manager = LocalTerminalManager()
        manager.createSession()
        XCTAssertNotNil(manager.activeSession)
        XCTAssertEqual(manager.activeSession?.id, manager.activeSessionID)
    }

    // MARK: - activeSessionID 自动切换

    @MainActor
    func test_activeSessionID_switchesToRemaining_onClose() {
        let manager = LocalTerminalManager()
        manager.createSession() // session 0
        let session0ID = manager.activeSessionID!
        manager.createSession() // session 1
        let session1ID = manager.activeSessionID!

        // 关闭当前活跃 session（session 1），应自动切换到 session 0
        manager.closeSession(id: session1ID)
        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.activeSessionID, session0ID)
    }

    @MainActor
    func test_activeSessionID_staysNil_afterClosingLast() {
        let manager = LocalTerminalManager()
        manager.createSession()
        let id = manager.activeSessionID!
        manager.closeSession(id: id)
        XCTAssertNil(manager.activeSessionID)
    }

    // MARK: - terminateAll

    @MainActor
    func test_terminateAll_clearsEverything() {
        let manager = LocalTerminalManager()
        manager.createSession()
        manager.createSession()
        XCTAssertEqual(manager.sessions.count, 2)

        manager.terminateAll()
        XCTAssertTrue(manager.sessions.isEmpty)
        XCTAssertNil(manager.activeSessionID)
        XCTAssertNil(manager.activeSession)
    }

    // MARK: - renameSession

    @MainActor
    func test_renameSession_updatesTitle() {
        let manager = LocalTerminalManager()
        manager.createSession()
        let id = manager.activeSessionID!

        manager.renameSession(id: id, title: "My Shell")
        let session = manager.sessions.first { $0.id == id }
        XCTAssertEqual(session?.title, "My Shell")
        XCTAssertTrue(session?.isCustomTitle ?? false)
    }
}
