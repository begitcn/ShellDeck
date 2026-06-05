import Foundation
import Observation
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
    private(set) var pingMs: Double = 0

    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var cachedServer: Server?

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
        self.cachedServer = server
        setupCallbacks()
    }

    private func setupCallbacks() {
        terminalViewModel.onDisconnect = { [weak self] in
            guard let self else { return }
            Task {
                await self.disconnect()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let server = self.cachedServer, self.state == .disconnected else { return }
                await self.connect(to: server)
            }
        }
    }

    func connect(to server: Server) async {
        guard state == .disconnected else { return }
        state = .connecting
        cachedServer = server

        do {
            let citadelClient = try await SSHService.connect(to: server)
            self.client = citadelClient
            state = .connected

            startTerminal()
            setupMonitor()
            setupPing()
            await setupSFTP()
        } catch let error as SSHError {
            guard state != .disconnected else { return }
            state = .failed(error.localizedDescription)
        } catch {
            guard state != .disconnected else { return }
            state = .failed(SSHError.connectionFailed(error).localizedDescription)
        }
    }

    func disconnect() async {
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil
        cachedServer = nil
        pingMs = 0
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

    // MARK: - Ping

    private func setupPing() {
        guard client != nil else { return }
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let client = self.client else { break }
                do {
                    let start = ContinuousClock.now
                    _ = try await client.executeCommand("echo p")
                    let elapsed = start.duration(to: ContinuousClock.now)
                    let sec = Double(elapsed.components.seconds)
                    let atto = Double(elapsed.components.attoseconds)
                    self.pingMs = sec * 1000.0 + atto / 1_000_000_000_000_000.0
                } catch {
                    self.pingMs = -1
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
}
