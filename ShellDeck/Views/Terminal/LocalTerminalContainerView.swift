import SwiftUI
import SwiftTerm
import Darwin

private final class FocusableLocalTerminalView: LocalProcessTerminalView {
    private var lastUsableFrameSize: NSSize?

    override func setFrameSize(_ newSize: NSSize) {
        if terminal != nil, isCollapsed(newSize), lastUsableFrameSize != nil {
            return
        }

        super.setFrameSize(newSize)

        if !isCollapsed(newSize) {
            lastUsableFrameSize = newSize
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            window?.makeFirstResponder(self)
        }
    }

    private func isCollapsed(_ size: NSSize) -> Bool {
        size.width < 32 || size.height < 24
    }
}

struct LocalTerminalContainerView: NSViewRepresentable {
    let session: LocalTerminalSession
    @Binding var isRunning: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = FocusableLocalTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        context.coordinator.session = session
        context.coordinator.isRunningBinding = $isRunning
        TerminalAppearance.apply(to: terminal)

        let shell = LocalShellResolver.defaultLoginShell()
        terminal.startProcess(
            executable: shell,
            environment: LocalShellResolver.environment(for: shell),
            execName: LocalShellResolver.loginShellName(for: shell)
        )

        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // No-op once created
    }

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
        nsView.terminate()
    }
}

private enum LocalShellResolver {
    static func defaultLoginShell() -> String {
        if let userShell = shellFromUserRecord(), isExecutable(userShell) {
            return userShell
        }

        if let environmentShell = ProcessInfo.processInfo.environment["SHELL"],
           isExecutable(environmentShell) {
            return environmentShell
        }

        return "/bin/zsh"
    }

    static func loginShellName(for shell: String) -> String {
        "-\(URL(fileURLWithPath: shell).lastPathComponent)"
    }

    static func environment(for shell: String) -> [String] {
        let inherited = ProcessInfo.processInfo.environment
        var environment = inherited.filter { key, _ in
            preservedEnvironmentKeys.contains(key)
                || key.hasPrefix("LC_")
        }

        environment["SHELL"] = shell
        environment["TERM"] = "xterm-256color"
        environment["TERM_PROGRAM"] = "ShellDeck"

        return environment.map { "\($0.key)=\($0.value)" }
    }

    private static let preservedEnvironmentKeys: Set<String> = [
        "HOME",
        "LANG",
        "LOGNAME",
        "PATH",
        "TMPDIR",
        "USER"
    ]

    private static func shellFromUserRecord() -> String? {
        guard let user = getpwuid(getuid()),
              let shell = user.pointee.pw_shell else {
            return nil
        }

        let path = String(cString: shell)
        return path.isEmpty ? nil : path
    }

    private static func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}

extension LocalTerminalContainerView {
    final class Coordinator: LocalProcessTerminalViewDelegate {
        var session: LocalTerminalSession?
        var isRunningBinding: Binding<Bool>?

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            Task { @MainActor in
                session?.isRunning = false
                isRunningBinding?.wrappedValue = false
            }
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            Task { @MainActor in
                session?.title = title
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}
