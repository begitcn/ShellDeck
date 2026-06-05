import Foundation
import SwiftUI

@Observable
@MainActor
final class LocalTerminalManager {
    var sessions: [LocalTerminalSession] = []
    var activeSessionID: UUID?
    private var nextIndex: Int = 1

    var activeSession: LocalTerminalSession? {
        sessions.first { $0.id == activeSessionID }
    }

    func createSession() {
        let session = LocalTerminalSession(
            title: "Terminal \(nextIndex)",
            shellType: "zsh",
            workingDirectory: "~"
        )
        nextIndex += 1
        sessions.append(session)
        activeSessionID = session.id
    }

    func closeSession(id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].terminate()
        sessions.remove(at: idx)
        if activeSessionID == id {
            activeSessionID = sessions.first?.id
        }
    }

    func renameSession(id: UUID, title: String) {
        if let session = sessions.first(where: { $0.id == id }) {
            session.title = title
            session.isCustomTitle = true
        }
    }

    func updateWorkingDirectory(id: UUID, directory: String) {
        if let session = sessions.first(where: { $0.id == id }) {
            session.workingDirectory = abbreviateHomePath(directory)
        }
    }

    func terminateAll() {
        for session in sessions { session.terminate() }
        sessions.removeAll()
        activeSessionID = nil
    }

    private func abbreviateHomePath(_ path: String) -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homeDir) {
            return "~" + String(path.dropFirst(homeDir.count))
        }
        return path
    }
}
