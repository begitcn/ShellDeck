import SwiftUI
import SwiftTerm
import Darwin

private final class FocusableLocalTerminalView: LocalProcessTerminalView {
    private var lastUsableFrameSize: NSSize?

    override func setFrameSize(_ newSize: NSSize) {
        if isCollapsed(newSize) {
            if lastUsableFrameSize != nil {
                return
            } else {
                // Initial layout or tab switch before frame is resolved:
                // set to a sensible default size instead of a collapsed tiny size
                let defaultSize = NSSize(width: 800, height: 600)
                super.setFrameSize(defaultSize)
                lastUsableFrameSize = defaultSize
                return
            }
        }

        super.setFrameSize(newSize)
        lastUsableFrameSize = newSize
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            window?.makeFirstResponder(self)
        }
    }

    private func isCollapsed(_ size: NSSize) -> Bool {
        size.width < 100 || size.height < 80
    }
}

struct LocalTerminalContainerView: NSViewRepresentable {
    @Environment(LocalTerminalManager.self) var manager
    let session: LocalTerminalSession
    @Binding var isRunning: Bool
    let isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = FocusableLocalTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        context.coordinator.session = session
        context.coordinator.isRunningBinding = $isRunning
        context.coordinator.onProcessTerminated = { [manager, sessionID = session.id] in
            withAnimation {
                manager.closeSession(id: sessionID)
            }
        }
        TerminalAppearance.apply(to: terminal)

        // Set running state immediately on process start
        DispatchQueue.main.async {
            session.isRunning = true
            isRunning = true
        }

        let shell = LocalShellResolver.defaultLoginShell()
        terminal.startProcess(
            executable: shell,
            environment: LocalShellResolver.environment(for: shell),
            execName: LocalShellResolver.loginShellName(for: shell)
        )

        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        if isActive, let window = nsView.window, window.firstResponder != nsView {
            DispatchQueue.main.async {
                window.makeFirstResponder(nsView)
            }
        }
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

        if environment["LANG"] == nil {
            if let preferredLang = Locale.preferredLanguages.first {
                if preferredLang.hasPrefix("zh-Hant") {
                    environment["LANG"] = "zh_TW.UTF-8"
                } else if preferredLang.hasPrefix("zh") {
                    environment["LANG"] = "zh_CN.UTF-8"
                } else if preferredLang.hasPrefix("ja") {
                    environment["LANG"] = "ja_JP.UTF-8"
                } else if preferredLang.hasPrefix("ko") {
                    environment["LANG"] = "ko_KR.UTF-8"
                } else {
                    environment["LANG"] = "en_US.UTF-8"
                }
            } else {
                environment["LANG"] = "en_US.UTF-8"
            }
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
        var onProcessTerminated: (() -> Void)?

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            Task { @MainActor in
                session?.isRunning = false
                isRunningBinding?.wrappedValue = false
                onProcessTerminated?()
            }
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            Task { @MainActor in
                guard let session = session else { return }
                if !session.isCustomTitle {
                    session.title = title
                }
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}
