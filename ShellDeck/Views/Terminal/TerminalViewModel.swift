import Foundation
import SSHClient

@MainActor
@Observable
final class TerminalViewModel {
    private(set) var isConnected = false
    private var shell: SSHShell?
    private var readTask: Task<Void, Never>?

    /// 当 SSH 有输出到来时，TerminalContainerView 会设置此回调将字节喂给 TerminalView。
    var onOutput: ((ArraySlice<UInt8>) -> Void)?

    func startSession(shell: SSHShell) {
        if readTask != nil { close() }
        self.shell = shell
        isConnected = true

        readTask = Task { [weak self] in
            do {
                for try await data in shell.data {
                    guard !Task.isCancelled else { break }
                    self?.onOutput?(ArraySlice<UInt8>(data))
                }
            } catch {
                await MainActor.run { self?.isConnected = false }
            }
            await MainActor.run { self?.isConnected = false }
        }
    }

    func send(data: ArraySlice<UInt8>) {
        let raw = Data(data)
        Task { [shell] in
            do {
                try await shell?.write(raw)
            } catch {
                print("[ShellDeck] SSH write error: \(error)")
            }
        }
    }

    func close() {
        readTask?.cancel()
        readTask = nil
        shell = nil
        isConnected = false
    }
}
