import SwiftUI
import SwiftTerm
import Darwin

private final class FocusableLocalTerminalView: LocalProcessTerminalView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            window?.makeFirstResponder(self)
        }
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
        terminal.configureNativeColors()
        terminal.startProcess(executable: "/bin/zsh")

        // Fix: set process group and foreground pgrp from parent
        // forkpty()'s login_tty() may fail on macOS, leaving zsh without controlling terminal
        if terminal.process.shellPid > 0 {
            setpgid(terminal.process.shellPid, terminal.process.shellPid)
            tcsetpgrp(terminal.process.childfd, terminal.process.shellPid)
        }

        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // No-op once created
    }

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
        nsView.terminate()
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
