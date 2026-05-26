import XCTest
import SwiftData
@testable import ShellDeck

final class ServerModelTests: XCTestCase {
    @MainActor
    func test_server_defaultValues() {
        let server = Server(host: "192.168.1.1", username: "admin")
        XCTAssertEqual(server.host, "192.168.1.1")
        XCTAssertEqual(server.port, 22)
        XCTAssertEqual(server.username, "admin")
        XCTAssertEqual(server.authTypeEnum, .password)
    }

    @MainActor
    func test_server_authTypePersistence() {
        let server = Server(host: "example.com", username: "root", authType: .privateKey)
        XCTAssertEqual(server.authTypeEnum, .privateKey)
        server.authTypeEnum = .password
        XCTAssertEqual(server.authTypeEnum, .password)
    }

    @MainActor
    func test_server_displayName_fallback() {
        let unnamed = Server(host: "10.0.0.1", username: "user")
        XCTAssertTrue(unnamed.displayName.isEmpty)

        let named = Server(displayName: "My Server", host: "10.0.0.1", username: "user")
        XCTAssertEqual(named.displayName, "My Server")
    }
}
