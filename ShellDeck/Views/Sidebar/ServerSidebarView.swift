import SwiftUI
import SwiftData

struct ServerSidebarView: View {
    @Query(sort: \ServerGroup.name) var groups: [ServerGroup]
    @Query(sort: \Server.displayName) var servers: [Server]
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: SidebarItem?
    let localManager: LocalTerminalManager
    let connectionStates: [UUID: ServerConnection.State]
    let onConnect: (Server) -> Void
    let onDisconnect: (Server) -> Void
    let onNewLocalSession: () -> Void

    @AppStorage("appTheme") private var appTheme: String = AppTheme.dark.rawValue

    @State private var showSettingsSheet = false
    @State private var searchText = ""

    @State private var showAddSheet = false
    @State private var showDeleteConfirmation = false
    @State private var serverToDelete: Server?
    @State private var editingServer: Server?

    @State private var showRenameLocalSheet = false
    @State private var localSessionToRename: LocalTerminalSession?
    @State private var renameLocalTitle = ""

    @State private var showAddGroupSheet = false
    @State private var newGroupName = ""
    @State private var showRenameGroupSheet = false
    @State private var groupToRename: ServerGroup?
    @State private var renameGroupName = ""
    @State private var showDeleteGroupConfirmation = false
    @State private var groupToDelete: ServerGroup?

    @State private var expandedGroups: Set<UUID> = []

    private let ungroupedSectionID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private var filteredServers: [Server] {
        searchText.isEmpty ? servers : servers.filter { s in
            s.displayName.localizedCaseInsensitiveContains(searchText) ||
            s.host.localizedCaseInsensitiveContains(searchText) ||
            s.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            searchBar
            unifiedList
        }
        .navigationTitle("")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showAddSheet) { AddServerView() }
        .sheet(item: $editingServer) { server in AddServerView(server: server) }
        .sheet(isPresented: $showAddGroupSheet) { addGroupSheet }
        .sheet(isPresented: $showRenameGroupSheet) { renameGroupSheet }
        .sheet(isPresented: $showRenameLocalSheet) { renameLocalSheet }
        .sheet(isPresented: $showSettingsSheet) { SettingsView() }
        .confirmationDialog("确认删除", isPresented: $showDeleteConfirmation, presenting: serverToDelete)
        { server in
            Button("删除", role: .destructive) { deleteServer(server); if case .server(let id) = selection, id == server.id { selection = nil } }
            Button("取消", role: .cancel) {}
        } message: { server in
            Text("确定要删除「\(server.displayName.isEmpty ? server.host : server.displayName)」吗？此操作不可撤销。")
        }
        .confirmationDialog("确认删除分组", isPresented: $showDeleteGroupConfirmation, presenting: groupToDelete)
        { group in
            Button("删除", role: .destructive) { deleteGroup(group) }
            Button("取消", role: .cancel) {}
        } message: { group in
            Text("确定要删除分组「\(group.name)」吗？分组内的服务器将变为未分组状态。")
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 6) {
            Text("ShellDeck")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                showSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("偏好设置")
            Menu {
                Button("服务器", systemImage: "server.rack") { showAddSheet = true }
                Button("分组", systemImage: "folder") { showAddGroupSheet = true }
                Divider()
                Button("本地终端", systemImage: "terminal") { onNewLocalSession() }
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("新建会话")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.caption)
            TextField("搜索服务器或终端...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(7)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.quaternary, lineWidth: 0.5)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    // MARK: - Unified List

    private var unifiedList: some View {
        List(selection: $selection) {
            // === SSH Server Groups ===
            if groups.isEmpty {
                flatList
            } else {
                groupedList
                ungroupedSection
            }

            // === Local Terminal Section ===
            localTerminalSection
        }
        .listStyle(.sidebar)
        .overlay { emptyOverlay }
    }

    // MARK: - SSH Servers

    private var flatList: some View {
        let items = filteredServers
        return ForEach(items) { server in
            serverRow(server)
                .tag(SidebarItem.server(server.id))
                .contextMenu { contextMenuItems(for: server) }
        }
    }

    private var groupedList: some View {
        let displayedGroups = groups
        return ForEach(displayedGroups) { group in
            let groupServers = filteredServers.filter { $0.group?.id == group.id }
            if !groupServers.isEmpty || filteredServers.isEmpty {
                Section {
                    if expandedGroups.contains(group.id) {
                        ForEach(groupServers) { server in
                            serverRow(server)
                                .tag(SidebarItem.server(server.id))
                                .contextMenu { contextMenuItems(for: server) }
                                .padding(.leading, 12)
                        }
                    }
                } header: {
                    coloredSectionHeader(name: group.name, isExpanded: expandedGroups.contains(group.id))
                        .contextMenu { groupContextMenuItems(for: group) }
                        .onTapGesture { toggleGroup(group.id) }
                }
            }
        }
    }

    @ViewBuilder
    private var ungroupedSection: some View {
        let ungroupedServers = filteredServers.filter { $0.group == nil }
        if !ungroupedServers.isEmpty {
            Section {
                if expandedGroups.contains(ungroupedSectionID) {
                    ForEach(ungroupedServers) { server in
                        serverRow(server)
                            .tag(SidebarItem.server(server.id))
                            .contextMenu { contextMenuItems(for: server) }
                            .padding(.leading, 12)
                    }
                }
            } header: {
                coloredSectionHeader(name: "未分组", isExpanded: expandedGroups.contains(ungroupedSectionID), color: .gray)
                    .onTapGesture { toggleGroup(ungroupedSectionID) }
            }
        }
    }

    // MARK: - Local Terminal Section

    @ViewBuilder
    private var localTerminalSection: some View {
        let items = localManager.sessions
        Section {
            if expandedGroups.contains(localTerminalSectionID) {
                ForEach(items) { session in
                    localTerminalRow(session)
                        .tag(SidebarItem.local(session.id))
                        .padding(.leading, 12)
                }
            }
        } header: {
            HStack(spacing: 4) {
                Image(systemName: expandedGroups.contains(localTerminalSectionID) ? "chevron.down" : "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption2)
                    .frame(width: 8)
                Text("本地终端")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                Spacer()
                Button { onNewLocalSession() } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("新建本地终端")
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.purple)
                    .frame(width: 2.5)
                    .padding(.vertical, 4)
            }
            .padding(.horizontal, 2)
            .padding(.top, 4)
            .contentShape(Rectangle())
            .onTapGesture { toggleGroup(localTerminalSectionID) }
        }
    }

    @State private var localTerminalSectionID = UUID()

    private func localTerminalRow(_ session: LocalTerminalSession) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(.purple)
                .font(.caption)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.callout)
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    Text("\(session.shellType) · \(session.workingDirectory)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                withAnimation { localManager.closeSession(id: session.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(3)
                    .background(.quaternary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("关闭终端")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu {
            Button("重命名", systemImage: "pencil") {
                localSessionToRename = session
                renameLocalTitle = session.title
                showRenameLocalSheet = true
            }
            Divider()
            Button("关闭", role: .destructive) {
                withAnimation { localManager.closeSession(id: session.id) }
            }
        }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if filteredServers.isEmpty && localManager.sessions.isEmpty {
            ContentUnavailableView("没有会话", systemImage: "terminal",
                description: Text("添加服务器或新建本地终端"))
        }
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {}
    }

    // MARK: - Colored Section Header

    private func coloredSectionHeader(name: String, isExpanded: Bool, color: Color? = nil) -> some View {
        let resolvedColor = color ?? groupColor(for: name)
        return HStack(spacing: 4) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .foregroundStyle(.tertiary)
                .font(.caption2)
                .frame(width: 8)
            Text(name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(resolvedColor)
                .frame(width: 2.5)
                .padding(.vertical, 4)
        }
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
    }

    private func groupColor(for name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("生产") || lower.contains("prod") || lower.contains("prd") {
            return .red
        } else if lower.contains("预发布") || lower.contains("staging") || lower.contains("stage") || lower.contains("uat") {
            return .orange
        } else if lower.contains("开发") || lower.contains("dev") || lower.contains("test") || lower.contains("测试") {
            return .green
        } else if lower.contains("个人") || lower.contains("personal") || lower.contains("home") {
            return .blue
        }
        return Color.accentColor
    }

    // MARK: - Group Toggle

    private func toggleGroup(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if expandedGroups.contains(id) {
                expandedGroups.remove(id)
            } else {
                expandedGroups.removeAll()
                expandedGroups.insert(id)
            }
        }
    }

    // MARK: - Group Context Menu

    @ViewBuilder
    private func groupContextMenuItems(for group: ServerGroup) -> some View {
        Button("重命名", systemImage: "pencil") {
            groupToRename = group; renameGroupName = group.name; showRenameGroupSheet = true
        }
        Divider()
        Button("删除分组", systemImage: "trash", role: .destructive) {
            groupToDelete = group; showDeleteGroupConfirmation = true
        }
    }

    // MARK: - Group Sheets

    private var addGroupSheet: some View {
        NavigationStack {
            Form {
                TextField("分组名称", text: $newGroupName)
            }
            .formStyle(.grouped)
            .navigationTitle("新建分组")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { newGroupName = ""; showAddGroupSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { createGroup() }
                        .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 300)
    }

    private var renameGroupSheet: some View {
        NavigationStack {
            Form {
                TextField("分组名称", text: $renameGroupName)
            }
            .formStyle(.grouped)
            .navigationTitle("重命名分组")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showRenameGroupSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { renameGroup() }
                        .disabled(renameGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 300)
    }

    // MARK: - Group Actions

    private func createGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let group = ServerGroup(name: name, sortOrder: groups.count)
        modelContext.insert(group)
        _ = withAnimation { expandedGroups.insert(group.id) }
        newGroupName = ""
        showAddGroupSheet = false
    }

    private func renameGroup() {
        guard let group = groupToRename else { return }
        let name = renameGroupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        group.name = name
        showRenameGroupSheet = false
        groupToRename = nil
    }

    private func deleteGroup(_ group: ServerGroup) {
        for server in group.servers { server.group = nil }
        modelContext.delete(group)
        expandedGroups.remove(group.id)
    }

    // MARK: - Row

    private func serverRow(_ server: Server) -> some View {
        HStack(spacing: 8) {
            statusDot(for: server)
            VStack(alignment: .leading, spacing: 1) {
                Text(server.displayName.isEmpty ? server.host : server.displayName)
                    .font(.callout)
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    Text("\(server.username)@\(server.host):\(server.port)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(server.authTypeEnum == .privateKey ? "KEY" : "SSH")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            connectionButton(for: server)
                .buttonStyle(.plain)
                .controlSize(.small)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    // MARK: - Status Dot

    private func statusDot(for server: Server) -> some View {
        Circle()
            .fill(statusColor(for: server))
            .frame(width: 7, height: 7)
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
                .font(.caption)
        case .connecting:
            ProgressView().controlSize(.small)
        case .connected:
            Button("断开") { onDisconnect(server) }
                .foregroundStyle(.red)
                .font(.caption)
        case .failed:
            Button("重试") { onConnect(server) }
                .foregroundStyle(.orange)
                .font(.caption)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for server: Server) -> some View {
        switch connectionStates[server.id] {
        case .none, .disconnected:
            Button("连接", systemImage: "play") { onConnect(server) }
        case .connecting: EmptyView()
        case .connected:
            Button("断开", systemImage: "stop") { onDisconnect(server) }
        case .failed:
            Button("重试", systemImage: "arrow.clockwise") { onConnect(server) }
        }
        Divider()
        Button("编辑", systemImage: "pencil") { editingServer = server }
        Divider()
        Button("删除", systemImage: "trash", role: .destructive) {
            serverToDelete = server; showDeleteConfirmation = true
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

    private var renameLocalSheet: some View {
        NavigationStack {
            Form {
                TextField("终端名称", text: $renameLocalTitle)
                    .onSubmit { renameLocalSession() }
            }
            .formStyle(.grouped)
            .navigationTitle("重命名终端")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showRenameLocalSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { renameLocalSession() }
                        .disabled(renameLocalTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 300)
    }

    private func renameLocalSession() {
        guard let session = localSessionToRename else { return }
        let title = renameLocalTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        localManager.renameSession(id: session.id, title: title)
        showRenameLocalSheet = false
        localSessionToRename = nil
    }
}
