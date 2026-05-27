import SwiftUI

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

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
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

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: goUp) {
                Image(systemName: "arrow.up")
            }
            .disabled(currentPath == "/")
            .help("返回上一级")

            TextField("路径", text: $currentPath)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .onSubmit {
                    Task { await loadDirectory() }
                }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }

            Button(action: { Task { await loadDirectory() } }) {
                Image(systemName: "arrow.clockwise")
            }
            .help("刷新")

            Button(action: uploadFile) {
                Image(systemName: "arrow.up.doc")
            }
            .help("上传文件")
        }
        .padding(8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if items.isEmpty && !isLoading {
            ContentUnavailableView(
                "空目录",
                systemImage: "folder",
                description: Text("此目录中没有文件")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        rowView(item: item, index: index)
                        Divider()
                            .padding(.leading, 28)
                    }
                }
            }
        }
    }

    private func rowView(item: SFTPItem, index: Int) -> some View {
        let isSelected = selectedItem == item.id
        return HStack(spacing: 8) {
            Image(systemName: item.isDirectory ? "folder" : "doc")
                .foregroundStyle(item.isDirectory ? .blue : .secondary)
                .frame(width: 20)

            Text(item.name)
                .lineLimit(1)

            Spacer()

            Text(item.isDirectory ? "—" : formattedSize(item.size))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            Text(item.modificationTime.map(formattedDate) ?? "—")
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.3) : (index % 2 == 1 ? Color(nsColor: .alternatingContentBackgroundColors.last ?? .controlBackgroundColor).opacity(0.5) : Color.clear))
                .padding(.leading, 4)
        }
        .contentShape(Rectangle())
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
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard let window = viewWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let remotePath = self.currentPath == "/" ? "/\(url.lastPathComponent)" : "\(self.currentPath)/\(url.lastPathComponent)"
            let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
            let fileSize = (attrs[.size] as? UInt64) ?? 0
            let task = TransferTask(fileName: url.lastPathComponent, type: .upload, totalBytes: fileSize)
            self.sftpService.transferTasks.append(task)
            Task {
                do {
                    try await self.sftpService.uploadFile(from: url, to: remotePath, task: task)
                    await self.loadDirectory()
                } catch {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.showError = true
                    }
                }
            }
        }
    }

    private var viewWindow: NSWindow? {
        NSApplication.shared.keyWindow
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
