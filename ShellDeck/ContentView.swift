import SwiftUI
import SwiftData
import Citadel

struct ContentView: View {
    private enum DetailTab: Hashable {
        case terminal
        case fileManager
        case monitor
        case info
    }

    @State private var selectedServer: Server?
    @State private var connections: [UUID: ServerConnection] = [:]
    @State private var selectedTabsByServer: [UUID: DetailTab] = [:]
    @State private var filePathsByServer: [UUID: String] = [:]

    var body: some View {
        NavigationSplitView {
            ServerSidebarView(
                selection: $selectedServer,
                connectionStates: connectionStates,
                onConnect: { connect(to: $0) },
                onDisconnect: { disconnect($0) }
            )
        } detail: {
            detailView
                .toolbar {
                    if let server = selectedServer, connections[server.id]?.state == .connected {
                        ToolbarItem {
                            Button("断开连接") { disconnect(server) }
                        }
                    }
                }
        }
    }

    private var connectionStates: [UUID: ServerConnection.State] {
        connections.mapValues(\.state)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        if let server = selectedServer {
            if let conn = connections[server.id] {
                connectionContentView(conn, server: server)
            } else {
                disconnectedServerView(server)
            }
        } else {
            ContentUnavailableView(
                "选择一个服务器",
                systemImage: "server.rack",
                description: Text("在左侧选择一台服务器，或点击 + 添加新服务器")
            )
        }
    }

    @ViewBuilder
    private func connectionContentView(_ conn: ServerConnection, server: Server) -> some View {
        switch conn.state {
        case .disconnected:
            disconnectedServerView(server)
        case .connecting:
            connectingView
        case .connected:
            connectedView(for: conn, server: server)
        case .failed(let error):
            failedView(error, server: server)
        }
    }

    // MARK: - 未选中 / 未连接

    @ViewBuilder
    private func disconnectedServerView(_ server: Server) -> some View {
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

    private func connectedView(for conn: ServerConnection, server: Server) -> some View {
        TabView(selection: selectedTabBinding(for: server.id)) {
            TerminalContainerView(viewModel: conn.terminalViewModel)
                .tag(DetailTab.terminal)
                .tabItem {
                    Label("终端", systemImage: "terminal")
                }

            if let sftpService = conn.sftpService {
                FileListView(
                    sftpService: sftpService,
                    currentPath: filePathBinding(for: server.id)
                )
                    .tag(DetailTab.fileManager)
                    .tabItem {
                        Label("文件管理", systemImage: "folder")
                    }
            }

            if let monitorService = conn.monitorService {
                SystemMonitorView(monitorService: monitorService)
                    .tag(DetailTab.monitor)
                    .tabItem {
                        Label("系统监控", systemImage: "gauge.medium")
                    }
            }

            serverInfoTab(server)
                .tag(DetailTab.info)
                .tabItem {
                    Label("信息", systemImage: "info.circle")
                }
        }
    }

    // MARK: - 连接失败

    private func failedView(_ error: String, server: Server) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("连接失败")
                .font(.title2)
                .bold()
            Text(error)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("重试") { connect(to: server) }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 信息 Tab

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
        let conn = ServerConnection(server: server)
        connections[server.id] = conn
        Task { await conn.connect(to: server) }
    }

    private func disconnect(_ server: Server) {
        guard let conn = connections.removeValue(forKey: server.id) else { return }
        Task { await conn.disconnect() }
    }

    private func selectedTabBinding(for serverID: UUID) -> Binding<DetailTab> {
        Binding(
            get: { selectedTabsByServer[serverID] ?? .terminal },
            set: { selectedTabsByServer[serverID] = $0 }
        )
    }

    private func filePathBinding(for serverID: UUID) -> Binding<String> {
        Binding(
            get: { filePathsByServer[serverID] ?? "/" },
            set: { filePathsByServer[serverID] = $0 }
        )
    }
}

#Preview {
    ContentView()
}
