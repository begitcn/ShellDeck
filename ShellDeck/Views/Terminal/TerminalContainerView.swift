import SwiftUI
import SwiftTerm

private final class FocusableTerminalView: TerminalView {
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

private final class TerminalPaddingContainer: NSView {
    let terminalView: FocusableTerminalView
    
    init(terminalView: FocusableTerminalView, padding: CGFloat = 5) {
        self.terminalView = terminalView
        super.init(frame: .zero)
        
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalView)
        
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: topAnchor, constant: padding),
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

struct TerminalContainerView: NSViewRepresentable {
    let viewModel: TerminalViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let terminal = FocusableTerminalView(frame: .zero)
        terminal.terminalDelegate = context.coordinator
        TerminalAppearance.apply(to: terminal)
        context.coordinator.connect(viewModel: viewModel, terminal: terminal)
        
        let container = TerminalPaddingContainer(terminalView: terminal)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? TerminalPaddingContainer else { return }
        let terminal = container.terminalView
        
        if context.coordinator.viewModel !== viewModel {
            context.coordinator.viewModel?.onOutput = nil
            terminal.terminal.resetToInitialState()
            context.coordinator.connect(viewModel: viewModel, terminal: terminal)
        }

        // When the SSH tab becomes visible again, force a full redraw of the existing buffer.
        context.coordinator.scheduleDisplayRefresh(for: terminal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            context.coordinator.scheduleDisplayRefresh(for: terminal)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.viewModel?.onOutput = nil
    }
}

extension TerminalContainerView {
    final class Coordinator: TerminalViewDelegate {
        private(set) var viewModel: TerminalViewModel?
        private var lastStableSize: (cols: Int, rows: Int)?
        private var isOutputConnected = false

        func connect(viewModel: TerminalViewModel, terminal: TerminalView) {
            self.viewModel = viewModel
            
            let cols = terminal.terminal.cols
            let rows = terminal.terminal.rows
            if cols >= 15 && rows >= 3 {
                lastStableSize = (cols, rows)
                isOutputConnected = true
                viewModel.onOutput = { [weak terminal] bytes in
                    terminal?.feed(byteArray: bytes)
                }
                viewModel.changeTerminalSize(cols: cols, rows: rows)
            } else {
                isOutputConnected = false
            }
            
            scheduleDisplayRefresh(for: terminal)
        }

        // MARK: - TerminalViewDelegate

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            viewModel?.send(data: data)
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            guard newCols >= 15, newRows >= 3 else {
                if let stable = lastStableSize {
                    DispatchQueue.main.async { [weak source] in
                        source?.resize(cols: stable.cols, rows: stable.rows)
                    }
                }
                return
            }
            lastStableSize = (newCols, newRows)
            viewModel?.changeTerminalSize(cols: newCols, rows: newRows)

            if !isOutputConnected {
                isOutputConnected = true
                viewModel?.onOutput = { [weak source] bytes in
                    source?.feed(byteArray: bytes)
                }
            }
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
