# Local Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local terminal emulator support with multi-tab management, independent from SSH servers.

**Architecture:** Use SwiftTerm's built-in `LocalProcessTerminalView` (NSView subclass) wrapped in NSViewRepresentable. Sidebar gets a Picker to toggle between SSH and Local modes. Local mode uses a TabView with ephemeral terminal tabs.

**Tech Stack:** SwiftTerm `LocalProcessTerminalView` (wraps `forkpty()` + PTY), SwiftUI `TabView`, `@Observable`

---

## Critical Prerequisite: Sandbox

**The app sandbox MUST be disabled** for local terminal support. SwiftTerm's `LocalProcess` uses `forkpty()` to spawn child processes, which is blocked by macOS App Sandbox. SSH via Citadel uses Network.framework and works fine without sandbox.

**Action:** Remove `com.apple.security.app-sandbox` from `ShellDeck/App/Entitlements.entitlements`.

This is acceptable because:
- ShellDeck is a developer tool — users intentionally run commands
- SSH via Citadel already works without sandbox (uses Network.framework)
- Keychain access works without sandbox
- All major terminal emulators (Terminal.app, iTerm2, Warp) run without sandbox

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `ShellDeck/App/Entitlements.entitlements` | Modify | Remove sandbox entitlement |
| `ShellDeck/Services/LocalTerminalManager.swift` | Create | Manage local terminal sessions |
| `ShellDeck/Views/Terminal/LocalTerminalView.swift` | Create | Tabbed local terminal UI |
| `ShellDeck/Views/Terminal/LocalTerminalContainerView.swift` | Create | NSViewRepresentable wrapper for LocalProcessTerminalView |
| `ShellDeck/Views/Sidebar/ServerSidebarView.swift` | Modify | Add mode Picker + local terminal list |
| `ShellDeck/ContentView.swift` | Modify | Route between SSH and local modes |

---

### Task 1: Disable App Sandbox

**Files:**
- Modify: `ShellDeck/App/Entitlements.entitlements`

- [ ] **Step 1: Remove sandbox entitlement**

Remove the `com.apple.security.app-sandbox` key and its value from the entitlements file. The file should become:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Commit**

```bash
git add ShellDeck/App/Entitlements.entitlements
git commit -m "Disable app sandbox for local terminal support"
```

---

### Task 2: Local Terminal Manager

**Files:**
- Create: `ShellDeck/Services/LocalTerminalManager.swift`

- [ ] **Step 1: Create LocalTerminalManager**

```swift
import Foundation
import SwiftUI

@Observable
@MainActor
final class LocalTerminalManager {
    var sessions: [LocalTerminalSession] = []
    var activeSessionID: UUID?
    private var nextIndex: Int = 1

    var activeSession: LocalTerminalSession? {
        sessions.first { $0.id == activeSessionID }
    }

    func createSession() {
        let session = LocalTerminalSession(title: "Terminal \(nextIndex)")
        nextIndex += 1
        sessions.append(session)
        activeSessionID = session.id
    }

    func closeSession(id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].terminate()
        sessions.remove(at: idx)
        if activeSessionID == id {
            activeSessionID = sessions.first?.id
        }
    }

    func renameSession(id: UUID, title: String) {
        sessions.first { $0.id == id }?.title = title
    }

    func terminateAll() {
        for session in sessions { session.terminate() }
        sessions.removeAll()
        activeSessionID = nil
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add ShellDeck/Services/LocalTerminalManager.swift
git commit -m "Add LocalTerminalManager for ephemeral local terminal sessions"
```

---

### Task 3: Local Terminal Session Model

**Files:**
- Create: `ShellDeck/Models/LocalTerminalSession.swift`

- [ ] **Step 1: Create LocalTerminalSession**

```swift
import Foundation

@MainActor
final class LocalTerminalSession: Identifiable {
    let id = UUID()
    var title: String
    var isRunning = false

    init(title: String) {
        self.title = title
    }

    func terminate() {
        isRunning = false
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add ShellDeck/Models/LocalTerminalSession.swift
git commit -m "Add LocalTerminalSession model"
```

---

### Task 4: Local Terminal Container View

**Files:**
- Create: `ShellDeck/Views/Terminal/LocalTerminalContainerView.swift`

- [ ] **Step 1: Create LocalTerminalContainerView**

This wraps SwiftTerm's `LocalProcessTerminalView` (which is an NSView) in SwiftUI via NSViewRepresentable.

```swift
import SwiftUI
import SwiftTerm

private final class FocusableLocalTerminalView: LocalProcessTerminalView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            window?.makeFirstResponder(self)
        }
    }
}

struct LocalTerminalContainerView: NSViewRepresentable {
    let session: LocalTerminalSession
    @Binding var isRunning: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = FocusableLocalTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        context.coordinator.session = session
        context.coordinator.isRunningBinding = $isRunning
        terminal.configureNativeColors()
        terminal.startProcess(executable: "/bin/zsh")
        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // No-op: session is immutable once created
    }

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
        nsView.terminate()
    }
}

extension LocalTerminalContainerView {
    final class Coordinator: LocalProcessTerminalViewDelegate {
        var session: LocalTerminalSession?
        var isRunningBinding: Binding<Bool>?

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            Task { @MainActor in
                session?.isRunning = false
                isRunningBinding?.wrappedValue = false
            }
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            Task { @MainActor in
                session?.title = title
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add ShellDeck/Views/Terminal/LocalTerminalContainerView.swift
git commit -m "Add LocalTerminalContainerView wrapping SwiftTerm LocalProcessTerminalView"
```

---

### Task 5: Local Terminal Tab View

**Files:**
- Create: `ShellDeck/Views/Terminal/LocalTerminalView.swift`

- [ ] **Step 1: Create LocalTerminalView**

```swift
import SwiftUI

struct LocalTerminalView: View {
    @Environment(LocalTerminalManager.self) var manager

    var body: some View {
        Group {
            if manager.sessions.isEmpty {
                emptyView
            } else {
                tabView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("没有打开的终端")
                .font(.title2)
                .foregroundStyle(.secondary)
            Button("新建终端") {
                manager.createSession()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var tabView: some View {
        TabView(selection: $manager.activeSessionID) {
            ForEach(manager.sessions) { session in
                terminalTab(session: session)
                    .tag(session.id as UUID?)
                    .tabItem {
                        HStack(spacing: 4) {
                            Image(systemName: session.isRunning ? "terminal" : "xmark.circle")
                            Text(session.title)
                        }
                    }
                    .contextMenu {
                        Button("重命名") { /* TODO: rename sheet */ }
                        Divider()
                        Button("关闭", role: .destructive) {
                            manager.closeSession(id: session.id)
                        }
                    }
            }
        }
    }

    private func terminalTab(session: LocalTerminalSession) -> some View {
        LocalTerminalContainerView(
            session: session,
            isRunning: Binding(
                get: { session.isRunning },
                set: { session.isRunning = $0 }
            )
        )
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add ShellDeck/Views/Terminal/LocalTerminalView.swift
git commit -m "Add LocalTerminalView with tabbed terminal management"
```

---

### Task 6: Sidebar Mode Toggle

**Files:**
- Modify: `ShellDeck/Views/Sidebar/ServerSidebarView.swift`

- [ ] **Step 1: Add SidebarMode enum and mode picker to ServerSidebarView**

Add at the top of the file, after the imports:

```swift
enum SidebarMode: String, CaseIterable, Identifiable {
    case ssh = "SSH 服务器"
    case local = "本地终端"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ssh: return "server.rack"
        case .local: return "terminal"
        }
    }
}
```

Add new properties to `ServerSidebarView`:

```swift
@Binding var sidebarMode: SidebarMode
@Binding var localSelection: UUID?
let localManager: LocalTerminalManager
```

Replace the `body` property:

```swift
var body: some View {
    VStack(spacing: 0) {
        modePicker
        Divider()
        if sidebarMode == .ssh {
            sshContent
        } else {
            localContent
        }
    }
    .navigationTitle(sidebarMode == .ssh ? "服务器" : "本地终端")
    .toolbar { toolbarContent }
    .sheet(isPresented: $showAddSheet) { AddServerView() }
    .sheet(item: $editingServer) { server in AddServerView(server: server) }
    .sheet(isPresented: $showAddGroupSheet) { addGroupSheet }
    .sheet(isPresented: $showRenameGroupSheet) { renameGroupSheet }
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
```

Add the mode picker and local content views:

```swift
// MARK: - Mode Picker

private var modePicker: some View {
    Picker("模式", selection: $sidebarMode) {
        ForEach(SidebarMode.allCases) { mode in
            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
        }
    }
    .pickerStyle(.segmented)
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
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
            HStack(spacing: 8) {
                Image(systemName: session.isRunning ? "terminal" : "xmark.circle")
                    .foregroundStyle(session.isRunning ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.headline)
                    Text(session.isRunning ? "运行中" : "已退出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .tag(session.id as UUID?)
            .contextMenu {
                Button("重命名") { /* TODO */ }
                Divider()
                Button("关闭", role: .destructive) {
                    manager.closeSession(id: session.id)
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
```

Update the toolbar to handle local mode:

```swift
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
```

Rename `emptyOverlay` to only apply in SSH mode:

```swift
private var emptyOverlay: some View {
    servers.isEmpty
        ? AnyView(ContentUnavailableView("没有服务器", systemImage: "server.rack",
            description: Text("点击 + 添加你的第一台服务器")))
        : AnyView(EmptyView())
}
```

- [ ] **Step 2: Update Preview**

Replace the `#Preview` block:

```swift
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
```

- [ ] **Step 3: Commit**

```bash
git add ShellDeck/Views/Sidebar/ServerSidebarView.swift
git commit -m "Add sidebar mode toggle between SSH servers and local terminals"
```

---

### Task 7: ContentView Routing

**Files:**
- Modify: `ShellDeck/ContentView.swift`

- [ ] **Step 1: Add state and environment for local mode**

Add new properties to `ContentView`:

```swift
@State private var sidebarMode: SidebarMode = .ssh
@State private var localSelection: UUID?
@State private var localManager = LocalTerminalManager()
```

- [ ] **Step 2: Update NavigationSplitView to pass mode bindings**

Replace the sidebar section:

```swift
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
        .toolbar {
            if sidebarMode == .ssh, let server = selectedServer, connections[server.id]?.state == .connected {
                ToolbarItem {
                    Button("断开连接") { disconnect(server) }
                }
            }
        }
}
.environment(localManager)
```

- [ ] **Step 3: Update detailView to route by mode**

Replace the `detailView` computed property:

```swift
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
```

- [ ] **Step 4: Commit**

```bash
git add ShellDeck/ContentView.swift
git commit -m "Route ContentView between SSH and local terminal modes"
```

---

### Task 8: Build Verification

- [ ] **Step 1: Build the project**

```bash
xcodebuild -project ShellDeck.xcodeproj -scheme ShellDeck -configuration Debug build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Fix any compilation errors**

If there are errors, fix them and rebuild.

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "Fix build errors for local terminal feature"
```

---

## Verification Checklist

After all tasks are complete, verify:

1. App launches without crash
2. Sidebar shows segmented picker: "SSH 服务器" / "本地终端"
3. Switching to "本地终端" shows empty state with "新建终端" button
4. Clicking + creates a new terminal tab with zsh prompt
5. Typing commands produces output
6. Multiple tabs can be created and switched between
7. Closing a tab kills the process
8. Switching back to SSH mode shows server list unchanged
9. SSH connections still work normally
10. Ctrl+C in local terminal sends SIGINT to shell
