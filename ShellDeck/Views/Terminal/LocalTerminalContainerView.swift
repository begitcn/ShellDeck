import SwiftUI
import SwiftTerm
import Darwin

final class FocusableLocalTerminalView: LocalProcessTerminalView {
    private var lastUsableFrameSize: NSSize?

    override func setFrameSize(_ newSize: NSSize) {
        if isCollapsed(newSize) {
            if lastUsableFrameSize != nil {
                return
            } else {
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

final class LocalTerminalPaddingContainer: NSView {
    weak var terminalView: FocusableLocalTerminalView?

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
        if let terminalView = terminalView {
            let bg = terminalView.nativeBackgroundColor
            self.wantsLayer = true
            self.layer?.backgroundColor = bg.cgColor
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let terminalView = terminalView {
            let bg = terminalView.nativeBackgroundColor
            bg.setFill()
            dirtyRect.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let terminalView = terminalView {
            window?.makeFirstResponder(terminalView)
        }
    }
}

final class TerminalCoordinator: LocalProcessTerminalViewDelegate {
    var session: LocalTerminalSession?
    var onProcessTerminated: (() -> Void)?
    var onDirectoryUpdate: ((String) -> Void)?

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            session?.isRunning = false
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

enum LocalShellResolver {
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

struct TerminalHostView: NSViewRepresentable {
    let activeSessionID: UUID?
    @Environment(LocalTerminalManager.self) var manager

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.autoresizesSubviews = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let activeID = activeSessionID else {
            for (_, entry) in manager.terminalEntries {
                entry.container.isHidden = true
            }
            return
        }

        // 确保活跃 session 的终端视图已初始化
        manager.setupTerminalIfNeeded(for: activeID)

        // 原则: 每个终端 NSView 只创建一次, 永不 removeFromSuperview
        // 切换仅通过 isHidden 实现, 避免 SwiftTerm 渲染管道因视图树变更而中断
        for (id, entry) in manager.terminalEntries {
            let container = entry.container
            if container.superview !== nsView {
                container.frame = nsView.bounds
                container.autoresizingMask = [.width, .height]
                nsView.addSubview(container)
            }
            container.isHidden = (id != activeID)
            container.frame = nsView.bounds
        }

        // 将 first responder 交给活跃终端
        if let activeEntry = manager.terminalEntries[activeID],
           let terminalView = activeEntry.container.terminalView,
           let window = nsView.window,
           window.firstResponder !== terminalView {
            window.makeFirstResponder(terminalView)
        }

        // 清理已关闭 session 残留的容器 (sessions 中已移除但 terminalEntries 仍存在)
        let aliveIDs = Set(manager.sessions.map(\.id))
        for (id, entry) in manager.terminalEntries where !aliveIDs.contains(id) {
            entry.container.removeFromSuperview()
        }
    }
}
