import SwiftUI
import UniformTypeIdentifiers

struct FileListView: View {
    let sftpService: SFTPService
    @Binding var currentPath: String

    @State private var items: [SFTPItem] = []
    @State private var selectedItem: SFTPItem.ID?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showDeleteConfirmation = false
    @State private var itemToDelete: SFTPItem?
    @State private var loadToken = UUID()
    @State private var lastTapTime: Date?
    
    @State private var hoveredItem: SFTPItem.ID? = nil
    @State private var isEditingPath = false
    @State private var isDropTargeted = false
    @State private var showHiddenFiles = false

    struct BreadcrumbItem: Identifiable {
        let id = UUID()
        let name: String
        let fullPath: String
    }

    private func breadcrumbs(from path: String) -> [BreadcrumbItem] {
        var breadcrumbs = [BreadcrumbItem(name: "/", fullPath: "/")]
        let parts = path.split(separator: "/").map(String.init)
        var current = ""
        for part in parts {
            current += "/" + part
            breadcrumbs.append(BreadcrumbItem(name: part, fullPath: current))
        }
        return breadcrumbs
    }

    private var filteredItems: [SFTPItem] {
        showHiddenFiles ? items : items.filter { !$0.name.hasPrefix(".") }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            dropZoneHint
            TransferProgressView(
                tasks: sftpService.transferTasks,
                onDismissCompleted: { sftpService.dismissCompletedTasks() },
                onDismissTask: { sftpService.removeTask($0) }
            )
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert("错误", isPresented: $showError, presenting: errorMessage) { _ in
            Button("确定") {}
        } message: { message in
            Text(message)
        }
        .confirmationDialog(
            "确认删除",
            isPresented: $showDeleteConfirmation,
            presenting: itemToDelete
        ) { item in
            Button("删除", role: .destructive) {
                Task { await performDelete(item) }
            }
            Button("取消", role: .cancel) {}
        } message: { item in
            Text("确定要删除「\(item.name)」吗？此操作不可撤销。")
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if isDropTargeted {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("释放以上传到 \(currentPath)")
                        .font(.callout)
                        .foregroundStyle(Color.accentColor)
                }
                .fontWeight(.medium)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color.accentColor.opacity(0.08))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            Task { await loadDirectory() }
        }
        .onChange(of: serviceIdentity) { _, _ in
            selectedItem = nil
            items = []
            loadToken = UUID()
            Task { await loadDirectory() }
        }
    }

    private var serviceIdentity: ObjectIdentifier {
        ObjectIdentifier(sftpService)
    }

    // MARK: - Toolbar

    private var dropZoneHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.doc")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("拖放文件或文件夹到此处上传")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 10) {
            Button(action: goUp) {
                Image(systemName: "chevron.left")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.plain)
            .disabled(currentPath == "/")
            .foregroundStyle(currentPath == "/" ? .tertiary : .primary)
            .help("返回上一级")

            if isEditingPath {
                TextField("路径", text: $currentPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onSubmit {
                        isEditingPath = false
                        Task { await loadDirectory() }
                    }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(breadcrumbs(from: currentPath)) { item in
                            Button(action: {
                                currentPath = item.fullPath
                                Task { await loadDirectory() }
                            }) {
                                Text(item.name)
                                    .font(.body.monospaced())
                                    .foregroundStyle(item.fullPath == currentPath ? .primary : Color.accentColor)
                                    .fontWeight(item.fullPath == currentPath ? .semibold : .regular)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(item.fullPath == currentPath ? Color.primary.opacity(0.06) : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                            
                            if item.fullPath != currentPath {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Button(action: { isEditingPath.toggle() }) {
                Image(systemName: isEditingPath ? "folder" : "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isEditingPath ? "显示面包屑导航" : "直接编辑路径文本")

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: { Task { await loadDirectory() } }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("刷新")

            Button(action: { showHiddenFiles.toggle() }) {
                Image(systemName: showHiddenFiles ? "eye" : "eye.slash")
            }
            .buttonStyle(.plain)
            .help(showHiddenFiles ? "隐藏隐藏文件" : "显示隐藏文件")

            Button(action: uploadFile) {
                Image(systemName: "plus")
                    .fontWeight(.semibold)
                Text("上传")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(Color.accentColor)
            .help("上传文件到当前目录")
        }
        .padding(8)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    isEditingPath = true
                }
        )
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if filteredItems.isEmpty && !isLoading {
            ContentUnavailableView(
                "空目录",
                systemImage: "folder",
                description: Text("此目录中没有文件")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                fileGridHeader
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            rowView(item: item, index: index)
                            Divider()
                                .padding(.leading, 28)
                        }
                    }
                }
                activeTransferBar
            }
        }
    }

    // MARK: - Grid Header

    private var fileGridHeader: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .frame(width: 16)
                    .hidden()
                Text("名称")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)

            Text("大小")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 80, alignment: .trailing)

            Text("修改日期")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 150, alignment: .leading)
                .padding(.leading, 8)

            Text("权限")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 90, alignment: .leading)
                .padding(.leading, 8)
        }
        .foregroundStyle(.tertiary)
        .padding(.vertical, 6)
        .padding(.trailing, 10)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Row

    private func rowView(item: SFTPItem, index: Int) -> some View {
        let isSelected = selectedItem == item.id
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: item.isDirectory ? "folder.fill" : "doc.text")
                    .foregroundStyle(item.isDirectory ? Color.accentColor : .secondary)
                    .frame(width: 16)

                Text(item.name)
                    .font(.callout)
                    .fontWeight(item.isDirectory ? .medium : .regular)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)

            Text(item.isDirectory ? "—" : formattedSize(item.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            Text(item.modificationTime.map(formattedDate) ?? "—")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
                .padding(.leading, 8)

            Text(item.permissions ?? "—")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 90, alignment: .leading)
                .padding(.leading, 8)
        }
        .padding(.vertical, 4)
        .padding(.trailing, 10)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : (hoveredItem == item.id ? Color.primary.opacity(0.04) : (index % 2 == 0 ? Color.primary.opacity(0.015) : Color.clear)))
        )
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered {
                hoveredItem = item.id
            } else if hoveredItem == item.id {
                hoveredItem = nil
            }
        }
        .onTapGesture {
            handleTap(item: item)
        }
        .contextMenu {
            if item.isDirectory {
                Button("打开") {
                    currentPath = item.path
                    Task { await loadDirectory() }
                }
            } else {
                Button("下载") { downloadItem(item) }
            }
            Divider()
            Button("删除", role: .destructive) {
                itemToDelete = item
                showDeleteConfirmation = true
            }
        }
    }

    // MARK: - Active Transfer Bar

    @ViewBuilder
    private var activeTransferBar: some View {
        if let activeTask = sftpService.transferTasks.first(where: { !$0.isTerminalStatus }) {
            VStack(spacing: 4) {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.doc.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text(activeTask.fileName)
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    if activeTask.totalBytes > 0 {
                        Text("\(String(format: "%.0f", activeTask.progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(formattedSize(activeTask.transferredBytes)) / \(formattedSize(activeTask.totalBytes))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                if activeTask.totalBytes > 0 {
                    ProgressView(value: activeTask.progress)
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
            }
            .background(Color.primary.opacity(0.02))
        }
    }

    // MARK: - Actions

    private func handleTap(item: SFTPItem) {
        let now = Date()
        if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) < 0.3 {
            lastTapTime = nil
            if item.isDirectory {
                currentPath = item.path
                Task { await loadDirectory() }
            }
        } else {
            selectedItem = item.id
            lastTapTime = now
        }
    }

    private func goUp() {
        guard currentPath != "/" else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        currentPath = parent.isEmpty ? "/" : parent
        Task { await loadDirectory() }
    }

    @Sendable
    private func loadDirectory() async {
        let token = loadToken
        isLoading = true
        defer { isLoading = false }
        do {
            let directory = try await sftpService.listDirectory(at: currentPath)
            guard token == loadToken else { return }
            items = directory
        } catch {
            guard token == loadToken else { return }
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func downloadItem(_ item: SFTPItem) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.name
        panel.canCreateDirectories = true
        guard let window = viewWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let task = TransferTask(fileName: item.name, type: .download, totalBytes: item.size)
            self.sftpService.transferTasks.append(task)
            Task {
                do {
                    try await self.sftpService.downloadFile(remotePath: item.path, to: url, task: task)
                } catch {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.showError = true
                    }
                }
            }
        }
    }

    private func uploadFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard let window = viewWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await self.performUpload(url: url) }
        }
    }

    private var viewWindow: NSWindow? {
        NSApplication.shared.keyWindow
    }

    // MARK: - Drag & Drop

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard error == nil else { return }
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let nsurl = item as? URL {
                    url = nsurl
                } else {
                    url = nil
                }
                guard let url else { return }
                Task { @MainActor in
                    await self.performUpload(url: url)
                }
            }
        }
    }

    private func performUpload(url: URL) async {
        let remotePath = currentPath == "/" ? "/\(url.lastPathComponent)" : "\(currentPath)/\(url.lastPathComponent)"
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            let task = TransferTask(fileName: url.lastPathComponent, type: .upload, totalBytes: 0)
            sftpService.transferTasks.append(task)
            do {
                try await sftpService.uploadDirectory(from: url, to: remotePath, task: task)
                await loadDirectory()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        } else {
            let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
            let fileSize = (attrs[.size] as? UInt64) ?? 0
            let task = TransferTask(fileName: url.lastPathComponent, type: .upload, totalBytes: fileSize)
            sftpService.transferTasks.append(task)
            do {
                try await sftpService.uploadFile(from: url, to: remotePath, task: task)
                await loadDirectory()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func performDelete(_ item: SFTPItem) async {
        do {
            try await sftpService.deleteItem(at: item.path)
            await loadDirectory()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Helpers

    private func formattedSize(_ size: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
