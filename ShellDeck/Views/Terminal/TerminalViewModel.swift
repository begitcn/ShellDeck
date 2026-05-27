import Foundation
import Citadel
import NIOCore
import NIOSSH

@MainActor
@Observable
final class TerminalViewModel {
    private(set) var isConnected = false
    @ObservationIgnored
    private var ptyTask: Task<Void, Never>?
    @ObservationIgnored
    private var stdinWriter: TTYStdinWriter?
    @ObservationIgnored
    private var outputBuffer: [UInt8] = []
    @ObservationIgnored
    private var sessionToken = UUID()
    private let maxBufferedBytes = 256 * 1024
    @ObservationIgnored
    private var lastWindowSize: (cols: Int, rows: Int)?

    var onOutput: ((ArraySlice<UInt8>) -> Void)? {
        didSet {
            guard let onOutput, !outputBuffer.isEmpty else { return }
            onOutput(ArraySlice(outputBuffer))
        }
    }

    func startSession(client: SSHClient) {
        if ptyTask != nil { close() }
        isConnected = true
        outputBuffer.removeAll(keepingCapacity: true)
        lastWindowSize = nil
        let token = UUID()
        sessionToken = token

        let request = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: 80,
            terminalRowHeight: 24,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([.ECHO: 1])
        )

        ptyTask = Task { [weak self] in
            do {
                try await client.withPTY(request) { inbound, outbound in
                    await MainActor.run {
                        guard let self, self.sessionToken == token else { return }
                        self.stdinWriter = outbound
                    }
                    for try await output in inbound {
                        switch output {
                        case .stdout(let buffer):
                            await MainActor.run {
                                guard let self, self.sessionToken == token else { return }
                                let chunk = Array(buffer.readableBytesView)
                                self.appendToBuffer(chunk)
                                self.onOutput?(ArraySlice(chunk))
                            }
                        case .stderr:
                            break
                        }
                    }
                }
            } catch {
                print("[ShellDeck] PTY error: \(error)")
            }
            await MainActor.run {
                guard let self, self.sessionToken == token else { return }
                self.isConnected = false
            }
        }
    }

    func send(data: ArraySlice<UInt8>) {
        let raw = Data(data)
        Task { [writer = stdinWriter] in
            try? await writer?.write(ByteBuffer(bytes: raw))
        }
    }

    func close() {
        ptyTask?.cancel()
        ptyTask = nil
        stdinWriter = nil
        isConnected = false
        lastWindowSize = nil
        sessionToken = UUID()
    }

    func changeTerminalSize(cols: Int, rows: Int) {
        guard cols > 1, rows > 1 else { return }
        guard lastWindowSize?.cols != cols || lastWindowSize?.rows != rows else { return }
        lastWindowSize = (cols, rows)

        Task { [writer = stdinWriter] in
            try? await writer?.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
        }
    }

    private func appendToBuffer(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        outputBuffer.append(contentsOf: bytes)

        if outputBuffer.count > maxBufferedBytes {
            outputBuffer.removeFirst(outputBuffer.count - maxBufferedBytes)
        }
    }
}
