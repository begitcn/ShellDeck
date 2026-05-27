import SwiftUI
import SwiftTerm

private final class FocusableTerminalView: TerminalView {
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

struct TerminalContainerView: NSViewRepresentable {
    let viewModel: TerminalViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TerminalView {
        let terminal = FocusableTerminalView(frame: .zero)
        terminal.terminalDelegate = context.coordinator
        TerminalAppearance.apply(to: terminal)
        context.coordinator.connect(viewModel: viewModel, terminal: terminal)
        return terminal
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        if context.coordinator.viewModel !== viewModel {
            context.coordinator.viewModel?.onOutput = nil
            nsView.terminal.resetToInitialState()
            context.coordinator.connect(viewModel: viewModel, terminal: nsView)
        }

        // When the SSH tab becomes visible again, force a full redraw of the existing buffer.
        context.coordinator.scheduleDisplayRefresh(for: nsView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            context.coordinator.scheduleDisplayRefresh(for: nsView)
        }
    }

    static func dismantleNSView(_ nsView: TerminalView, coordinator: Coordinator) {
        coordinator.viewModel?.onOutput = nil
    }
}

extension TerminalContainerView {
    final class Coordinator: TerminalViewDelegate {
        private(set) var viewModel: TerminalViewModel?
        private var lastStableSize: (cols: Int, rows: Int)?

        func connect(viewModel: TerminalViewModel, terminal: TerminalView) {
            self.viewModel = viewModel
            viewModel.onOutput = { [weak terminal] bytes in
                terminal?.feed(byteArray: bytes)
            }
            scheduleDisplayRefresh(for: terminal)
        }

        // MARK: - TerminalViewDelegate

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            viewModel?.send(data: data)
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            guard newCols > 1, newRows > 1 else {
                if let stable = lastStableSize {
                    DispatchQueue.main.async { [weak source] in
                        source?.resize(cols: stable.cols, rows: stable.rows)
                    }
                }
                return
            }
            lastStableSize = (newCols, newRows)
            viewModel?.changeTerminalSize(cols: newCols, rows: newRows)
        }

        func scheduleDisplayRefresh(for terminal: TerminalView) {
            guard terminal.window != nil else { return }
            if let stable = lastStableSize, terminal.terminal.cols <= 1 || terminal.terminal.rows <= 1 {
                terminal.resize(cols: stable.cols, rows: stable.rows)
            }
            terminal.terminal.refresh(startRow: 0, endRow: max(0, terminal.terminal.rows - 1))
            terminal.needsDisplay = true
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
