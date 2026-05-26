import Foundation
import Citadel
import NIOCore
import NIOSSH

@MainActor
@Observable
final class TerminalViewModel {
    private(set) var isConnected = false
    private var ptyTask: Task<Void, Never>?
    private var stdinWriter: TTYStdinWriter?

    var onOutput: ((ArraySlice<UInt8>) -> Void)?

    func startSession(client: SSHClient) {
        if ptyTask != nil { close() }
        isConnected = true

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
                        self?.stdinWriter = outbound
                    }
                    for try await output in inbound {
                        switch output {
                        case .stdout(let buffer):
                            await MainActor.run {
                                self?.onOutput?(ArraySlice<UInt8>(buffer.readableBytesView))
                            }
                        case .stderr:
                            break
                        }
                    }
                }
            } catch {
                print("[ShellDeck] PTY error: \(error)")
            }
            await MainActor.run { self?.isConnected = false }
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
    }
}
