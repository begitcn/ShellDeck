import XCTest
@testable import ShellDeck

final class SSHErrorTests: XCTestCase {
    func test_error_descriptions() {
        XCTAssertNotNil(SSHError.keychainItemNotFound.errorDescription)
        XCTAssertNotNil(SSHError.notConnected.errorDescription)
        XCTAssertNotNil(SSHError.invalidPrivateKey.errorDescription)
    }
}
