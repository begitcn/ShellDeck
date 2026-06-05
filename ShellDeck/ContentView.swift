import SwiftUI
import SwiftData
import Citadel

enum SidebarItem: Hashable {
    case server(UUID)
    case local(UUID)
}

struct ContentView: View {
    private enum DetailTab: Hashable {
        case terminal
        case fileManager
        case monitor
        case info
    }

    @Query(sort: \Server.displayName) private var servers: [Server]
    @State private var sidebarSelection: SidebarItem?
    @State private var connections: [UUID: ServerConnection] = [:]
    @State private var connectTasks: [UUID: Task<Void, Never>] = [:]
    @State private var selectedTabsByServer: [UUID: DetailTab] = [:]
    @State private var filePathsByServer: [UUID: String] = [:]
    @State private var localManager = LocalTerminalManager()
    private let digits: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    private var selectedServer: Server? {
        guard case .server(let id) = sidebarSelection else { return nil }
        return servers.first(where: { $0.id == id })
    }

    private var localSelection: UUID? {
        guard case .local(let id) = sidebarSelection else { return nil }
        return id
    }

    var body: some View {
        NavigationSplitView {
            ServerSidebarView(
                selection: $sidebarSelection,
                localManager: localManager,
                connectionStates: connectionStates,
                onConnect: { connect(to: $0) },
                onDisconnect: { disconnect($0) },
                onNewLocalSession: { localManager.createSession() }
            )
        } detail: {
            detailView
                .navigationTitle(detailTitle)
                .toolbarTitleDisplayMode(.inline)
        }
        .environment(localManager)
        .background {
            ForEach(0..<9, id: \.self) { index in
                Button("") {
                    selectSidebarItem(at: index)
                }
                .keyboardShortcut(KeyEquivalent(digits[index]), modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
            }

            Button("") {
                openFileManagerTab()
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)

            Button("") {
                handleCommandT()
            }
            .keyboardShortcut("t", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        }
        .onChange(of: localManager.activeSessionID) { _, newValue in
            if let id = newValue, sidebarSelection != .local(id) {
                sidebarSelection = .local(id)
            }
        }
        .onAppear {
            if sidebarSelection == nil {
                if let firstServer = servers.first {
                    sidebarSelection = .server(firstServer.id)
                }
            }
        }
    }

    private var detailTitle: String {
        switch sidebarSelection {
        case .local(let id):
            return localManager.sessions.first(where: { $0.id == id })?.title ?? "本地终端"
        case .server(let id):
            if let server = servers.first(where: { $0.id == id }) {
                return server.displayName.isEmpty ? server.host : server.displayName
            }
            return "ShellDeck"
        case nil:
            return "ShellDeck"
        }
    }

    private var connectionStates: [UUID: ServerConnection.State] {
        connections.mapValues(\.state)
    }

    private var hasSSHConnection: Bool {
        guard case .server(let id) = sidebarSelection else { return false }
        return connections[id] != nil
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch sidebarSelection {
        case .local:
            LocalTerminalView()
        case .server(let id):
            if let server = servers.first(where: { $0.id == id }) {
                if let conn = connections[server.id] {
                    connectionContentView(conn, server: server)
                } else {
                    disconnectedServerView(server)
                }
            } else {
                emptySelectionView
            }
        case nil:
            emptySelectionView
        }
    }

    private var emptySelectionView: some View {
        ContentUnavailableView(
            "选择一个会话",
            systemImage: "terminal",
            description: Text("在左侧选择一台服务器或新建本地终端")
        )
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

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("正在安全建立连接...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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
                    ContentUnavailableView("监控服务未就绪", systemImage: "chart.xyaxis.line")
                }
            case .info:
                ServerInfoView(server: server, connection: conn)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomStatusBar(conn, server: server, selectedTab: selectedTab)
        }
        .toolbar {
            ToolbarItem {
                HStack(spacing: 0) {
                    tabButton(title: "终端", icon: "terminal", tab: .terminal, conn: conn, server: server)
                    tabButton(title: "文件", icon: "folder", tab: .fileManager, conn: conn, server: server)
                    tabButton(title: "监控", icon: "chart.bar", tab: .monitor, conn: conn, server: server)
                    tabButton(title: "信息", icon: "info.circle", tab: .info, conn: conn, server: server)
                }
            }
            ToolbarItem {
                HStack(spacing: 4) {
                    hostnameChip(server)
                    Button { disconnect(server) } label: {
                        Image(systemName: "power")
                    }
                    .foregroundStyle(.red)
                    .help("断开连接")
                }
            }
        }
    }

    private func tabButton(title: String, icon: String, tab: DetailTab, conn: ServerConnection, server: Server) -> some View {
        let isActive = (selectedTabsByServer[server.id] ?? .terminal) == tab
        return Button {
            selectedTabsByServer[server.id] = tab
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(isActive ? .semibold : .regular)
            }
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) {
                if isActive {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func hostnameChip(_ server: Server) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.green)
                .frame(width: 5, height: 5)
            Text(server.host)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func bottomStatusBar(_ conn: ServerConnection, server: Server, selectedTab: DetailTab) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(conn.state == .connected ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 5, height: 5)
            Text(conn.state == .connected ? "已连接" : "未连接")
                .font(.caption2)
                .foregroundStyle(conn.state == .connected ? Color.green : Color.gray)
            Text(server.host)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if selectedTab == .terminal {
                Text("◈ 80×24")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(formattedPing(conn.pingMs))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private func formattedPing(_ ms: Double) -> String {
        if ms < 0 {
            return "\u{27F3}  ping ..."
        }
        if ms == 0 {
            return "\u{27F3}  ping ..."
        }
        return String(format: "\u{27F3}  ping %.0fms", ms)
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

    // MARK: - Actions

    private func connect(to server: Server) {
        connectTasks[server.id]?.cancel()
        connectTasks[server.id] = Task {
            if let existing = connections[server.id] {
                await existing.disconnect()
            }
            guard !Task.isCancelled else { return }
            let conn = ServerConnection(server: server)
            connections[server.id] = conn
            await conn.connect(to: server)
        }
    }

    private func disconnect(_ server: Server) {
        connectTasks[server.id]?.cancel()
        connectTasks[server.id] = nil
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

    private func selectSidebarItem(at index: Int) {
        if case .local = sidebarSelection {
            guard index >= 0 && index < localManager.sessions.count else { return }
            sidebarSelection = .local(localManager.sessions[index].id)
        } else {
            guard index >= 0 && index < servers.count else { return }
            sidebarSelection = .server(servers[index].id)
        }
    }

    private func openFileManagerTab() {
        guard case .server(let id) = sidebarSelection else { return }
        selectedTabsByServer[id] = .fileManager
    }

    private func handleCommandT() {
        if case .local = sidebarSelection {
            localManager.createSession()
        } else if let server = selectedServer {
            selectedTabsByServer[server.id] = .terminal
        }
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

// MARK: - Server Info View

struct ServerInfoView: View {
    let server: Server
    let connection: ServerConnection

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(server.displayName.isEmpty ? server.host : server.displayName)
                        .font(.title)
                        .fontWeight(.bold)
                    Text("\(server.username)@\(server.host):\(server.port)")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                Divider()
                    .padding(.horizontal)

                VStack(spacing: 0) {
                    infoRow(label: "认证方式", value: server.authTypeEnum.displayName)
                    Divider()
                    infoRow(label: "连接状态", value: connection.state == .connected ? "已连接" : "未连接")
                    Divider()
                    infoRow(label: "端口", value: "\(server.port)")
                    if let last = server.lastConnectedAt {
                        Divider()
                        infoRow(label: "上次连接", value: last.formatted())
                    }
                    Divider()
                    infoRow(label: "创建时间", value: server.createdAt.formatted())
                    Divider()
                    infoRow(label: "SFTP", value: connection.sftpService != nil ? "可用" : "不可用")
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
            }
            .padding(.bottom, 20)
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#Preview {
    ContentView()
}
