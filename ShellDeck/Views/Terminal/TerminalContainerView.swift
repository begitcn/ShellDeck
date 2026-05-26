import SwiftUI
import SwiftTerm

private final class FocusableTerminalView: TerminalView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            window?.makeFirstResponder(self)
        }
    }
}

struct TerminalContainerView: NSViewRepresentable {
    let viewModel: TerminalViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> TerminalView {
        let terminal = FocusableTerminalView(frame: .zero)
        terminal.terminalDelegate = context.coordinator
        terminal.configureNativeColors()
        context.coordinator.setOutputHandler(terminal: terminal)
        return terminal
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        context.coordinator.viewModel = viewModel
    }

    static func dismantleNSView(_ nsView: TerminalView, coordinator: Coordinator) {
        coordinator.close()
    }
}

extension TerminalContainerView {
    final class Coordinator: TerminalViewDelegate {
        var viewModel: TerminalViewModel?

        init(viewModel: TerminalViewModel) {
            self.viewModel = viewModel
        }

        func setOutputHandler(terminal: TerminalView) {
            viewModel?.onOutput = { [weak terminal] bytes in
                terminal?.feed(byteArray: bytes)
            }
        }

        func close() {
            viewModel?.onOutput = nil
            viewModel?.close()
        }

        // MARK: - TerminalViewDelegate

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            viewModel?.send(data: data)
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            // TODO: send window-change to SSH server when SSHShell supports it
        }

        func scrolled(source: TerminalView, position: Double) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
