import Foundation
import Citadel

@MainActor
@Observable
final class ServerConnection {
    let serverID: UUID
    let serverName: String

    private(set) var state: State = .disconnected
    private(set) var client: SSHClient?
    let terminalViewModel = TerminalViewModel()
    private(set) var sftpService: SFTPService?
    private(set) var monitorService: MonitorService?

    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected): true
            case (.connecting, .connecting): true
            case (.connected, .connected): true
            case (.failed, .failed): true
            default: false
            }
        }
    }

    init(server: Server) {
        self.serverID = server.id
        self.serverName = server.displayName.isEmpty ? server.host : server.displayName
        
        setupCallbacks()
    }

    private func setupCallbacks() {
        terminalViewModel.onDisconnect = { [weak self] in
            guard let self else { return }
            Task {
                await self.disconnect()
            }
        }
    }

    func connect(to server: Server) async {
        guard state == .disconnected else { return }
        state = .connecting

        do {
            let citadelClient = try await SSHService.connect(to: server)
            self.client = citadelClient
            state = .connected

            startTerminal()
            setupMonitor()
            await setupSFTP()
        } catch let error as SSHError {
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(SSHError.connectionFailed(error).localizedDescription)
        }
    }

    func disconnect() async {
        terminalViewModel.close()
        monitorService?.stopMonitoring(clearHistory: true)
        monitorService = nil
        await sftpService?.disconnect()
        sftpService = nil
        await SSHService.disconnect(client)
        client = nil
        state = .disconnected
    }

    // MARK: - Sub-services

    private func startTerminal() {
        guard let client else { return }
        terminalViewModel.startSession(client: client)
    }

    private func setupMonitor() {
        guard let client else { return }
        let service = MonitorService()
        service.setup(client: client)
        monitorService = service
    }

    private func setupSFTP() async {
        guard let client else { return }
        let service = SFTPService()
        do {
            try await service.connect(client: client)
            sftpService = service
        } catch {
            print("[ShellDeck] SFTP 连接失败: \(error)")
        }
    }
}
