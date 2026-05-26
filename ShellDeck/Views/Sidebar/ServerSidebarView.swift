import SwiftUI
import SwiftData

struct ServerSidebarView: View {
    @Query(sort: \Server.displayName) var servers: [Server]
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: Server?
    @State private var showAddSheet = false

    var body: some View {
        List(selection: $selection) {
            ForEach(servers) { server in
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
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .tag(server)
                .contextMenu {
                    Button(role: .destructive) {
                        deleteServer(server)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("服务器")
        .toolbar {
            ToolbarItemGroup {
                if let selection, let server = servers.first(where: { $0.id == selection.id }) {
                    Button(role: .destructive) {
                        deleteServer(server)
                        self.selection = nil
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
    }

    private func deleteServer(_ server: Server) {
        KeychainHelper.delete(key: server.id.uuidString)
        KeychainHelper.delete(key: server.id.uuidString + ".key")
        KeychainHelper.delete(key: server.id.uuidString + ".passphrase")
        modelContext.delete(server)
    }
}

#Preview {
    NavigationStack {
        ServerSidebarView(selection: .constant(nil))
            .modelContainer(for: Server.self, inMemory: true)
    }
}
