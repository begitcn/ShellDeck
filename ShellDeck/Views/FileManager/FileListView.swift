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

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
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
        .background(isSelected ? Color.accentColor.opacity(0.3) : (index % 2 == 1 ? Color(nsColor: .alternatingContentBackgroundColors.last ?? .controlBackgroundColor).opacity(0.5) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedItem = item.id
        }
        .highPriorityGesture(TapGesture(count: 2).onEnded {
            selectedItem = item.id
            if item.isDirectory {
                currentPath = item.path
                Task { await loadDirectory() }
            }
        })
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

    private func goUp() {
        guard currentPath != "/" else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        currentPath = parent.isEmpty ? "/" : parent
        Task { await loadDirectory() }
    }

    @Sendable
    private func loadDirectory() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await sftpService.listDirectory(at: currentPath)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func downloadItem(_ item: SFTPItem) {
        NSLog("[ShellDeck] downloadItem start: \(item.name)")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.name
        panel.canCreateDirectories = true
        guard let window = viewWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            NSLog("[ShellDeck] downloadItem savePanel OK: \(url.path)")
            Task {
                do {
                    try await self.sftpService.downloadFile(remotePath: item.path, to: url)
                    NSLog("[ShellDeck] downloadItem done")
                } catch {
                    NSLog("[ShellDeck] downloadItem error: \(error)")
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
            Task {
                do {
                    try await self.sftpService.uploadFile(from: url, to: remotePath)
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
