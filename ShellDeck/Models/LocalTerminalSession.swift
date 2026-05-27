import Foundation

@MainActor
final class LocalTerminalSession: Identifiable {
    let id = UUID()
    var title: String
    var isRunning = false

    init(title: String) {
        self.title = title
    }

    func terminate() {
        isRunning = false
    }
}
