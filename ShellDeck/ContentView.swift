import SwiftUI
import SwiftData
import Citadel

struct ContentView: View {
    @State private var selectedServer: Server?
    @State private var sshService = SSHService()
    @State private var terminalViewModel = TerminalViewModel()
    @State private var sftpService: SFTPService?
    @State private var monitorService: MonitorService?

    var body: some View {
        NavigationSplitView {
            ServerSidebarView(selection: $selectedServer)
        } detail: {
            detailView
                .toolbar {
                    if case .connected = sshService.state {
                        ToolbarItem {
                            Button("断开连接") { disconnect() }
                        }
                    }
                }
        }
        .onChange(of: selectedServer?.id) { _, _ in
            disconnect()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch sshService.state {
        case .disconnected:
            disconnectedView
        case .connecting:
            connectingView
        case .connected:
            connectedView
        case .failed(let error):
            failedView(error)
        }
    }

    // MARK: - 未选中 / 未连接

    @ViewBuilder
    private var disconnectedView: some View {
        if let server = selectedServer {
            VStack(spacing: 20) {
                Image(systemName: "server.rack")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(server.displayName.isEmpty ? server.host : server.displayName)
                    .font(.title2)
                    .bold()
                HStack(spacing: 16) {
                    Label(server.host, systemImage: "network")
                    Label("\(server.port)", systemImage: "number")
                }
                .foregroundStyle(.secondary)
                Label("\(server.username)@\(server.host)", systemImage: "person")
                    .foregroundStyle(.secondary)
                Button("连接到服务器") {
                    connect(to: server)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        } else {
            ContentUnavailableView(
                "选择一个服务器",
                systemImage: "server.rack",
                description: Text("在左侧选择一台服务器，或点击 + 添加新服务器")
            )
        }
    }

    // MARK: - 连接中

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("正在安全建立连接...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 已连接

    private var connectedView: some View {
        TabView {
            TerminalContainerView(viewModel: terminalViewModel)
                .tabItem {
                    Label("终端", systemImage: "terminal")
                }

            if let sftpService {
                FileListView(sftpService: sftpService)
                    .tabItem {
                        Label("文件管理", systemImage: "folder")
                    }
            }

            if let monitorService {
                SystemMonitorView(monitorService: monitorService)
                    .tabItem {
                        Label("系统监控", systemImage: "gauge.medium")
                    }
            }

            if let server = selectedServer {
                serverInfoTab(server)
            }
        }
        .onAppear {
            if !terminalViewModel.isConnected {
                startTerminal()
            }
            if sftpService == nil {
                Task { await setupSFTP() }
            }
            if monitorService == nil {
                setupMonitor()
            }
        }
    }

    // MARK: - 连接失败

    private func failedView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("连接失败")
                .font(.title2)
                .bold()
            Text(error.localizedDescription)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if let server = selectedServer {
                Button("重试") { connect(to: server) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 信息 Tab（预留）

    private func serverInfoTab(_ server: Server) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                LabeledContent("名称", value: server.displayName.isEmpty ? "—" : server.displayName)
                LabeledContent("主机", value: server.host)
                LabeledContent("端口", value: "\(server.port)")
                LabeledContent("用户名", value: server.username)
                LabeledContent("认证方式", value: server.authTypeEnum.displayName)
            }
            .padding(.horizontal)
        }
        .tabItem {
            Label("信息", systemImage: "info.circle")
        }
    }

    // MARK: - Actions

    private func connect(to server: Server) {
        terminalViewModel = TerminalViewModel()
        Task { await sshService.connect(to: server) }
    }

    private func startTerminal() {
        guard case .connected = sshService.state, let client = sshService.client else { return }
        terminalViewModel.startSession(client: client)
    }

    private func setupMonitor() {
        guard monitorService == nil, let client = sshService.client else { return }
        let service = MonitorService()
        service.startMonitoring(client: client)
        monitorService = service
    }

    private func setupSFTP() async {
        guard sftpService == nil, let client = sshService.client else { return }
        let service = SFTPService()
        do {
            try await service.connect(client: client)
            sftpService = service
        } catch {
            print("[ShellDeck] SFTP 连接失败: \(error)")
        }
    }

    private func disconnect() {
        terminalViewModel.close()
        monitorService?.stopMonitoring()
        monitorService = nil
        Task {
            await sftpService?.disconnect()
            sftpService = nil
            await sshService.disconnect()
        }
    }
}

#Preview {
    ContentView()
}
