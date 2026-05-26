import SwiftUI
import SwiftData
import SSHClient

struct ContentView: View {
    @State private var selectedServer: Server?
    @State private var sshService = SSHService()
    @State private var terminalViewModel = TerminalViewModel()
    @State private var shell: SSHShell?

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

            if let server = selectedServer {
                serverInfoTab(server)
            }
        }
        .onAppear {
            if shell == nil {
                Task { await requestShell() }
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
        shell = nil
        Task { await sshService.connect(to: server) }
    }

    private func requestShell() async {
        guard case .connected = sshService.state else { return }
        do {
            let newShell = try await sshService.requestShell()
            shell = newShell
            terminalViewModel.startSession(shell: newShell)
        } catch {
            await sshService.disconnect()
        }
    }

    private func disconnect() {
        terminalViewModel.close()
        shell = nil
        Task { await sshService.disconnect() }
    }
}

#Preview {
    ContentView()
}
