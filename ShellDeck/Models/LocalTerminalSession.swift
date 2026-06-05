import Foundation
import Observation

@Observable
@MainActor
final class LocalTerminalSession: Identifiable {
    let id = UUID()
    var title: String
    var isRunning = false
    var isCustomTitle = false
    var shellType: String
    var workingDirectory: String

    init(title: String, shellType: String = "zsh", workingDirectory: String = "~") {
        self.title = title
        self.shellType = shellType
        self.workingDirectory = workingDirectory
    }

    func terminate() {
        isRunning = false
    }
}

