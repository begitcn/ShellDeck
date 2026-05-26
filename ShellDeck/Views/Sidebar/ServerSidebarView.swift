import SwiftUI
import SwiftData

struct ServerSidebarView: View {
    @Query(sort: \Server.displayName) var servers: [Server]
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: Server?
    let connectionStates: [UUID: ServerConnection.State]
    let onConnect: (Server) -> Void
    let onDisconnect: (Server) -> Void

    @State private var showAddSheet = false
    @State private var showDeleteConfirmation = false
    @State private var serverToDelete: Server?
    @State private var editingServer: Server?

    var body: some View {
        List(selection: $selection) {
            ForEach(servers) { server in
                serverRow(server)
                    .tag(server)
                    .onTapGesture { selection = server }
                    .contextMenu {
                        contextMenuItems(for: server)
                    }
            }
        }
        .navigationTitle("服务器")
        .toolbar {
            ToolbarItemGroup {
                if let selection, let server = servers.first(where: { $0.id == selection.id }) {
                    Button {
                        editingServer = server
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        serverToDelete = server
                        showDeleteConfirmation = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                Button {
                    showAddSheet = true
                } label: {
                    Label("添加", systemImage: "plus")
                }
            }
        }
        .overlay {
            if servers.isEmpty {
                ContentUnavailableView(
                    "没有服务器",
                    systemImage: "server.rack",
                    description: Text("点击 + 添加你的第一台服务器")
                )
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddServerView()
        }
        .sheet(item: $editingServer) { server in
            AddServerView(server: server)
        }
        .confirmationDialog(
            "确认删除",
            isPresented: $showDeleteConfirmation,
            presenting: serverToDelete
        ) { server in
            Button("删除", role: .destructive) {
                deleteServer(server)
                if selection?.id == server.id {
                    selection = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: { server in
            Text("确定要删除「\(server.displayName.isEmpty ? server.host : server.displayName)」吗？此操作不可撤销。")
        }
    }

    // MARK: - Row

    private func serverRow(_ server: Server) -> some View {
        HStack(spacing: 8) {
            statusDot(for: server)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName.isEmpty ? server.host : server.displayName)
                    .font(.headline)
                HStack(spacing: 4) {
                    Image(systemName: server.authTypeEnum == .password ? "key.fill" : "lock.fill")
                        .foregroundStyle(.secondary)
                    Text("\(server.username)@\(server.host):\(server.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            connectionButton(for: server)
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Status Dot

    private func statusDot(for server: Server) -> some View {
        Circle()
            .fill(statusColor(for: server))
            .frame(width: 8, height: 8)
    }

    private func statusColor(for server: Server) -> Color {
        switch connectionStates[server.id] {
        case .none, .disconnected: return .gray.opacity(0.3)
        case .connecting: return .orange
        case .connected: return .green
        case .failed: return .red
        }
    }

    // MARK: - Connection Button

    @ViewBuilder
    private func connectionButton(for server: Server) -> some View {
        switch connectionStates[server.id] {
        case .none, .disconnected:
            Button("连接") { onConnect(server) }
                .foregroundStyle(.blue)
        case .connecting:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        case .connected:
            Button("断开") { onDisconnect(server) }
                .foregroundStyle(.red)
        case .failed:
            Button("重试") { onConnect(server) }
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for server: Server) -> some View {
        switch connectionStates[server.id] {
        case .none, .disconnected:
            Button("连接", systemImage: "play") { onConnect(server) }
        case .connecting:
            EmptyView()
        case .connected:
            Button("断开", systemImage: "stop") { onDisconnect(server) }
        case .failed:
            Button("重试", systemImage: "arrow.clockwise") { onConnect(server) }
        }
        Divider()
        Button("编辑", systemImage: "pencil") { editingServer = server }
        Divider()
        Button("删除", systemImage: "trash", role: .destructive) {
            serverToDelete = server
            showDeleteConfirmation = true
        }
    }

    // MARK: - Actions

    private func deleteServer(_ server: Server) {
        onDisconnect(server)
        KeychainHelper.delete(key: server.id.uuidString)
        KeychainHelper.delete(key: server.id.uuidString + ".key")
        KeychainHelper.delete(key: server.id.uuidString + ".passphrase")
        modelContext.delete(server)
    }
}

#Preview {
    NavigationStack {
        ServerSidebarView(
            selection: .constant(nil),
            connectionStates: [:],
            onConnect: { _ in },
            onDisconnect: { _ in }
        )
        .modelContainer(for: Server.self, inMemory: true)
    }
}
