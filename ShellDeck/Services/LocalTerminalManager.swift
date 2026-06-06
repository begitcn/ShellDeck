import Foundation
import SwiftUI
import SwiftTerm

@Observable
@MainActor
final class LocalTerminalManager {
    var sessions: [LocalTerminalSession] = []
    var activeSessionID: UUID?
    private var nextIndex: Int = 1

    struct TerminalEntry {
        let container: LocalTerminalPaddingContainer
        let coordinator: TerminalCoordinator
    }

    @ObservationIgnored private(set) var terminalEntries: [UUID: TerminalEntry] = [:]

    var activeSession: LocalTerminalSession? {
        sessions.first { $0.id == activeSessionID }
    }

    var activeTerminalContainer: LocalTerminalPaddingContainer? {
        guard let id = activeSessionID else { return nil }
        return terminalEntries[id]?.container
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

    func setupTerminalIfNeeded(for sessionID: UUID) {
        guard terminalEntries[sessionID] == nil else { return }
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }

        let terminal = FocusableLocalTerminalView(frame: .zero)
        let coordinator = TerminalCoordinator()
        terminal.processDelegate = coordinator
        coordinator.session = session
        coordinator.onProcessTerminated = { [weak self, id = session.id] in
            Task { @MainActor in
                self?.closeSession(id: id)
            }
        }
        coordinator.onDirectoryUpdate = { [weak self, id = session.id] dir in
            self?.updateWorkingDirectory(id: id, directory: dir)
        }
        TerminalAppearance.apply(to: terminal)

        session.isRunning = true

        let shell = LocalShellResolver.defaultLoginShell()
        let shellName = URL(fileURLWithPath: shell).lastPathComponent
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        session.shellType = shellName
        session.workingDirectory = abbreviateHomePath(homeDir)

        terminal.startProcess(
            executable: shell,
            environment: LocalShellResolver.environment(for: shell),
            execName: LocalShellResolver.loginShellName(for: shell)
        )

        let container = LocalTerminalPaddingContainer(terminalView: terminal)
        terminalEntries[session.id] = TerminalEntry(container: container, coordinator: coordinator)
    }

    func closeSession(id: UUID) {
        if let entry = terminalEntries[id] {
            entry.container.terminalView?.terminate()
            terminalEntries.removeValue(forKey: id)
        }
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
        for entry in terminalEntries.values {
            entry.container.terminalView?.terminate()
        }
        terminalEntries.removeAll()
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
