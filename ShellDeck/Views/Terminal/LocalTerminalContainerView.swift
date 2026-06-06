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

private final class LocalTerminalPaddingContainer: NSView {
    let terminalView: FocusableLocalTerminalView
    
    init(terminalView: FocusableLocalTerminalView, padding: CGFloat = 5) {
        self.terminalView = terminalView
        super.init(frame: .zero)
        
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalView)
        
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        let bg = terminalView.nativeBackgroundColor
        self.wantsLayer = true
        self.layer?.backgroundColor = bg.cgColor
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let bg = terminalView.nativeBackgroundColor
        bg.setFill()
        dirtyRect.fill()
    }
    
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(terminalView)
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

    func makeNSView(context: Context) -> NSView {
        let terminal = FocusableLocalTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        context.coordinator.session = session
        context.coordinator.isRunningBinding = $isRunning
        context.coordinator.onProcessTerminated = { [manager, sessionID = session.id] in
            withAnimation {
                manager.closeSession(id: sessionID)
            }
        }
        context.coordinator.onDirectoryUpdate = { [manager, sessionID = session.id] dir in
            manager.updateWorkingDirectory(id: sessionID, directory: dir)
        }
        TerminalAppearance.apply(to: terminal)

        // Set running state immediately on process start
        DispatchQueue.main.async {
            session.isRunning = true
            isRunning = true
        }

        let shell = LocalShellResolver.defaultLoginShell()
        let shellName = URL(fileURLWithPath: shell).lastPathComponent
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.main.async {
            session.shellType = shellName
            session.workingDirectory = abbreviateHome(homeDir)
        }
        terminal.startProcess(
            executable: shell,
            environment: LocalShellResolver.environment(for: shell),
            execName: LocalShellResolver.loginShellName(for: shell)
        )

        let container = LocalTerminalPaddingContainer(terminalView: terminal)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? LocalTerminalPaddingContainer else { return }
        let terminal = container.terminalView
        
        if isActive, let window = terminal.window, window.firstResponder != terminal {
            DispatchQueue.main.async {
                window.makeFirstResponder(terminal)
            }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        guard let container = nsView as? LocalTerminalPaddingContainer else { return }
        container.terminalView.terminate()
    }

    private func abbreviateHome(_ path: String) -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homeDir) {
            return "~" + String(path.dropFirst(homeDir.count))
        }
        return path
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
        var onDirectoryUpdate: ((String) -> Void)?

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

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            guard let dir = directory else { return }
            onDirectoryUpdate?(dir)
        }
    }
}
