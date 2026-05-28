import SwiftUI
import SwiftData

enum SidebarMode: String, CaseIterable, Identifiable {
    case local = "本地终端"
    case ssh = "SSH 服务器"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ssh: return "server.rack"
        case .local: return "terminal"
        }
    }
}

struct ServerSidebarView: View {
    @Query(sort: \ServerGroup.name) var groups: [ServerGroup]
    @Query(sort: \Server.displayName) var servers: [Server]
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: Server?
    @Binding var sidebarMode: SidebarMode
    @Binding var localSelection: UUID?
    let localManager: LocalTerminalManager
    let connectionStates: [UUID: ServerConnection.State]
    let onConnect: (Server) -> Void
    let onDisconnect: (Server) -> Void

    @AppStorage("appTheme") private var appTheme: String = AppTheme.dark.rawValue

    @State private var updateService = UpdateService.shared
    @State private var showSettingsSheet = false

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

    var body: some View {
        VStack(spacing: 0) {
            modePicker
            Divider()
            if sidebarMode == .ssh {
                sshContent
            } else {
                localContent
            }
            Divider()
            themeFooterView
        }
        .navigationTitle(sidebarMode == .ssh ? "服务器" : "本地终端")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showAddSheet) { AddServerView() }
        .sheet(item: $editingServer) { server in AddServerView(server: server) }
        .sheet(isPresented: $showAddGroupSheet) { addGroupSheet }
        .sheet(isPresented: $showRenameGroupSheet) { renameGroupSheet }
        .sheet(isPresented: $showRenameLocalSheet) { renameLocalSheet }
        .sheet(isPresented: $showSettingsSheet) { SettingsView() }
        .confirmationDialog("确认删除", isPresented: $showDeleteConfirmation, presenting: serverToDelete)
        { server in
            Button("删除", role: .destructive) { deleteServer(server); if selection?.id == server.id { selection = nil } }
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

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("", selection: $sidebarMode) {
            ForEach(SidebarMode.allCases) { mode in
                Label(mode.rawValue, systemImage: mode.icon).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - SSH Content

    private var sshContent: some View {
        List(selection: $selection) {
            if groups.isEmpty {
                flatList
            } else {
                groupedList
                ungroupedSection
            }
        }
        .overlay { emptyOverlay }
    }

    // MARK: - Local Content

    private var localContent: some View {
        List(selection: $localSelection) {
            ForEach(localManager.sessions) { session in
                HStack(spacing: 10) {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(.green)
                        .imageScale(.medium)
                    
                    Text(session.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    // Trailing close button
                    Button(action: {
                        withAnimation {
                            localManager.closeSession(id: session.id)
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .help("关闭终端")
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .tag(session.id as UUID?)
                .contextMenu {
                    Button("重命名", systemImage: "pencil") {
                        localSessionToRename = session
                        renameLocalTitle = session.title
                        showRenameLocalSheet = true
                    }
                    Divider()
                    Button("关闭", role: .destructive) {
                        withAnimation {
                            localManager.closeSession(id: session.id)
                        }
                    }
                }
            }
        }
        .overlay {
            localManager.sessions.isEmpty
                ? AnyView(ContentUnavailableView(
                    "没有终端",
                    systemImage: "terminal",
                    description: Text("点击 + 新建本地终端")
                ))
                : AnyView(EmptyView())
        }
    }

    // MARK: - Sub-views (SSH)

    private var flatList: some View {
        ForEach(servers) { server in
            serverRow(server)
                .tag(server)
                .contextMenu { contextMenuItems(for: server) }
        }
    }

    private var groupedList: some View {
        ForEach(groups) { group in
            let groupServers = servers.filter { $0.group?.id == group.id }
            Section {
                if expandedGroups.contains(group.id) {
                    ForEach(groupServers) { server in
                        serverRow(server)
                            .tag(server)
                            .contextMenu { contextMenuItems(for: server) }
                    }
                }
            } header: {
                sectionHeader(name: group.name, isExpanded: expandedGroups.contains(group.id))
                    .contextMenu { groupContextMenuItems(for: group) }
                    .onTapGesture { toggleGroup(group.id) }
            }
        }
    }

    @ViewBuilder
    private var ungroupedSection: some View {
        let ungroupedServers = servers.filter { $0.group == nil }
        if !ungroupedServers.isEmpty {
            Section {
                if expandedGroups.contains(ungroupedSectionID) {
                    ForEach(ungroupedServers) { server in
                        serverRow(server)
                            .tag(server)
                            .contextMenu { contextMenuItems(for: server) }
                    }
                }
            } header: {
                sectionHeader(name: "未分组", isExpanded: expandedGroups.contains(ungroupedSectionID))
                    .onTapGesture { toggleGroup(ungroupedSectionID) }
            }
        }
    }

    private var emptyOverlay: some View {
        servers.isEmpty
            ? AnyView(ContentUnavailableView("没有服务器", systemImage: "server.rack",
                description: Text("点击 + 添加你的第一台服务器")))
            : AnyView(EmptyView())
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if sidebarMode == .ssh {
                if let selection, let server = servers.first(where: { $0.id == selection.id }) {
                    Button { editingServer = server } label: { Label("编辑", systemImage: "pencil") }
                    Button(role: .destructive) { serverToDelete = server; showDeleteConfirmation = true }
                        label: { Label("删除", systemImage: "trash") }
                }
                Menu {
                    Button("服务器", systemImage: "server.rack") { showAddSheet = true }
                    Button("分组", systemImage: "folder") { showAddGroupSheet = true }
                } label: { Label("添加", systemImage: "plus") }
            } else {
                Button { localManager.createSession() } label: { Label("新建终端", systemImage: "plus") }
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(name: String, isExpanded: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(width: 8)
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(name)
                .font(.headline)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Group Toggle

    private func toggleGroup(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if expandedGroups.contains(id) { expandedGroups.remove(id) }
            else { expandedGroups.insert(id) }
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
            Button("连接") { onConnect(server) }.foregroundStyle(.blue)
        case .connecting:
            ProgressView().controlSize(.small)
        case .connected:
            Button("断开") { onDisconnect(server) }.foregroundStyle(.red)
        case .failed:
            Button("重试") { onConnect(server) }.foregroundStyle(.orange)
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
                    .onSubmit {
                        renameLocalSession()
                    }
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

    private var themeFooterView: some View {
        HStack(spacing: 8) {
            Text("版本 v\(updateService.currentVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button(action: {
                showSettingsSheet = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("偏好设置与关于")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    NavigationStack {
        ServerSidebarView(
            selection: .constant(nil),
            sidebarMode: .constant(.ssh),
            localSelection: .constant(nil),
            localManager: LocalTerminalManager(),
            connectionStates: [:],
            onConnect: { _ in },
            onDisconnect: { _ in }
        )
        .modelContainer(for: Server.self, inMemory: true)
    }
}
