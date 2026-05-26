import XCTest
@testable import ShellDeck

final class TerminalViewModelTests: XCTestCase {
    func test_isConnected_startsFalse() {
        let vm = TerminalViewModel()
        XCTAssertFalse(vm.isConnected)
    }

    func test_close_resetsState() {
        let vm = TerminalViewModel()
        vm.close()
        XCTAssertFalse(vm.isConnected)
    }

    func test_send_doesNotCrash_withoutSession() {
        let vm = TerminalViewModel()
        vm.send(data: [0x68, 0x69][...])  // "hi"
    }
}
