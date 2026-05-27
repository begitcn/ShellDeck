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

    @Query(sort: \Server.displayName) private var servers: [Server]
    @State private var selectedServer: Server?
    @State private var connections: [UUID: ServerConnection] = [:]
    @State private var selectedTabsByServer: [UUID: DetailTab] = [:]
    @State private var filePathsByServer: [UUID: String] = [:]
    @State private var sidebarMode: SidebarMode = .local
    @State private var localSelection: UUID?
    @State private var localManager = LocalTerminalManager()

    var body: some View {
        NavigationSplitView {
            ServerSidebarView(
                selection: $selectedServer,
                sidebarMode: $sidebarMode,
                localSelection: $localSelection,
                localManager: localManager,
                connectionStates: connectionStates,
                onConnect: { connect(to: $0) },
                onDisconnect: { disconnect($0) }
            )
        } detail: {
            detailView
                .navigationTitle(detailTitle)
        }
        .environment(localManager)
        .onChange(of: localSelection) { _, newValue in
            if localManager.activeSessionID != newValue {
                localManager.activeSessionID = newValue
            }
        }
        .onChange(of: localManager.activeSessionID) { _, newValue in
            if localSelection != newValue {
                localSelection = newValue
            }
        }
        .onChange(of: sidebarMode) { _, newMode in
            if newMode == .local {
                if localSelection == nil {
                    localSelection = localManager.activeSessionID ?? localManager.sessions.first?.id
                }
                if localManager.activeSessionID == nil {
                    localManager.activeSessionID = localSelection
                }
            } else if newMode == .ssh {
                if selectedServer == nil, let firstServer = servers.first {
                    selectedServer = firstServer
                }
            }
        }
        .onChange(of: servers) { _, newServers in
            if selectedServer == nil, let firstServer = newServers.first {
                selectedServer = firstServer
            }
        }
        .onAppear {
            if sidebarMode == .local {
                localSelection = localManager.activeSessionID ?? localManager.sessions.first?.id
                localManager.activeSessionID = localSelection
            } else if selectedServer == nil, let firstServer = servers.first {
                selectedServer = firstServer
            }
        }
    }

    private var detailTitle: String {
        if sidebarMode == .local {
            return localManager.sessions.first(where: { $0.id == localSelection })?.title ?? "本地终端"
        } else if let server = selectedServer {
            return server.displayName.isEmpty ? server.host : server.displayName
        } else {
            return "ShellDeck"
        }
    }

    private var connectionStates: [UUID: ServerConnection.State] {
        connections.mapValues(\.state)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        if sidebarMode == .local {
            LocalTerminalView()
        } else if let server = selectedServer {
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

    // MARK: - 已连接

    private func connectedView(for conn: ServerConnection, server: Server) -> some View {
        let selectedTab = selectedTabsByServer[server.id] ?? .terminal
        return Group {
            switch selectedTab {
            case .terminal:
                TerminalContainerView(viewModel: conn.terminalViewModel)
            case .fileManager:
                if let sftpService = conn.sftpService {
                    FileListView(
                        sftpService: sftpService,
                        currentPath: filePathBinding(for: server.id)
                    )
                } else {
                    ContentUnavailableView("SFTP 未连接", systemImage: "folder.badge.minus")
                }
            case .monitor:
                if let monitorService = conn.monitorService {
                    SystemMonitorView(monitorService: monitorService)
                } else {
                    ContentUnavailableView("监控服务不可用", systemImage: "gauge.badge.minus")
                }
            case .info:
                serverInfoTab(server)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("视图切换", selection: selectedTabBinding(for: server.id)) {
                    Text("终端").tag(DetailTab.terminal)
                    if conn.sftpService != nil {
                        Text("文件管理").tag(DetailTab.fileManager)
                    }
                    if conn.monitorService != nil {
                        Text("系统监控").tag(DetailTab.monitor)
                    }
                    Text("信息").tag(DetailTab.info)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(action: { disconnect(server) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                        Text("断开")
                    }
                    .foregroundStyle(.red)
                }
                .help("断开与当前服务器的连接")
            }
        }
    }

    @ViewBuilder
    private func statusDot(for state: ServerConnection.State) -> some View {
        let color: Color = {
            switch state {
            case .disconnected: return .gray
            case .connecting: return .orange
            case .connected: return .green
            case .failed: return .red
            }
        }()
        Image(systemName: "circle.fill")
            .font(.system(size: 8))
            .foregroundStyle(color)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("服务器配置信息")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    VStack(spacing: 12) {
                        infoRow(label: "显示名称", value: server.displayName.isEmpty ? "—" : server.displayName, icon: "tag")
                        Divider()
                        infoRow(label: "主机名 / IP", value: server.host, icon: "network")
                        Divider()
                        infoRow(label: "端口", value: "\(server.port)", icon: "number")
                        Divider()
                        infoRow(label: "登录用户", value: server.username, icon: "person")
                        Divider()
                        infoRow(label: "认证方式", value: server.authTypeEnum.displayName, icon: "lock")
                    }
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                .padding(24)
            }
        }
    }

    @ViewBuilder
    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Actions

    private func connect(to server: Server) {
        if let existing = connections[server.id] {
            Task { await existing.disconnect() }
        }
        let conn = ServerConnection(server: server)
        connections[server.id] = conn
        Task { await conn.connect(to: server) }
    }

    private func disconnect(_ server: Server) {
        guard let conn = connections.removeValue(forKey: server.id) else { return }
        selectedTabsByServer[server.id] = nil
        filePathsByServer[server.id] = nil
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

// MARK: - Supporting Views

struct PulsatingDot: View {
    let color: Color
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 14, height: 14)
                .scaleEffect(scale)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: true)
                    ) {
                        scale = 1.6
                    }
                }
            
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
    }
}

#Preview {
    ContentView()
}
