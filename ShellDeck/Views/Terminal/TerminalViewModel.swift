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
    private var outputBuffer: [UInt8] = []
    private let maxBufferedBytes = 256 * 1024

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
                                let chunk = Array(buffer.readableBytesView)
                                self?.appendToBuffer(chunk)
                                self?.onOutput?(ArraySlice(chunk))
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

    private func appendToBuffer(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        outputBuffer.append(contentsOf: bytes)

        if outputBuffer.count > maxBufferedBytes {
            outputBuffer.removeFirst(outputBuffer.count - maxBufferedBytes)
        }
    }
}
