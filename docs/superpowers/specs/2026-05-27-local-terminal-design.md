# Local Terminal Feature Design

**Date:** 2026-05-27
**Status:** Approved
**Scope:** Add local terminal (non-SSH) support with multi-tab management

## Problem

ShellDeck currently only supports SSH connections. Users also need a local terminal emulator within the same app, without the overhead of SSH, file management, or system monitoring tabs.

## Requirements

1. **Sidebar toggle** — Switch between "SSH Servers" and "Local Terminals" views via a picker at the top of the sidebar
2. **Default shell** — Spawn `/bin/zsh` (user's default shell), no configuration needed
3. **Multi-tab management** — Standard TabView with `+` new tab, `x` close tab, tab switching
4. **No persistence** — Local terminal tabs are ephemeral; all cleared on app restart
5. **Independent detail view** — When in local terminal mode, the right panel shows only terminal tabs, completely decoupled from SSH server state

## Approach: SwiftTerm LocalProcess

Use SwiftTerm's built-in `LocalProcess` class, which wraps `forkpty()` + `posix_spawn()` for native PTY management. This is the standard approach — SwiftTerm was designed to support both SSH and local process modes.

Rejected alternatives:
- **Manual `forkpty()`** — ~200 lines of PTY management code, error-prone (zombie processes, fd leaks)
- **`Process` + pipes** — No job control (Ctrl+C, Ctrl+Z, fg/bg broken)

## Architecture

### New Types

#### `LocalTerminalSession` (new file: `ShellDeck/Views/Terminal/LocalTerminalSession.swift`)

```swift
@Observable
@MainActor
class LocalTerminalSession {
    let id: UUID
    var title: String
    let process: LocalProcess
    let terminal: Terminal
    var isRunning: Bool

    init(title: String) {
        self.id = UUID()
        self.title = title
        self.terminal = Terminal()
        self.process = LocalProcess(terminal: terminal)
        self.isRunning = false
    }

    func start() {
        process.start(delegate: nil)  // delegate will be set by view
        isRunning = true
    }

    func stop() {
        process.stop()
        isRunning = false
    }
}
```

#### `LocalTerminalManager` (new file: `ShellDeck/Services/LocalTerminalManager.swift`)

```swift
@Observable
@MainActor
class LocalTerminalManager {
    var sessions: [LocalTerminalSession] = []
    var activeSessionID: UUID?
    private var nextIndex: Int = 1

    var activeSession: LocalTerminalSession? {
        get { sessions.first { $0.id == activeSessionID } }
    }

    func createSession() {
        let session = LocalTerminalSession(title: "Terminal \(nextIndex)")
        nextIndex += 1
        sessions.append(session)
        activeSessionID = session.id
        session.start()
    }

    func closeSession(id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].stop()
        sessions.remove(at: idx)
        if activeSessionID == id {
            activeSessionID = sessions.first?.id
        }
    }

    func renameSession(id: UUID, title: String) {
        sessions.first { $0.id == id }?.title = title
    }
}
```

### Modified Types

#### `TerminalContainerView` — Extend to support local mode

Current: binds to `TerminalViewModel` (SSH mode).
Change: Accept an optional `LocalTerminalSession` as alternative input.

```swift
struct TerminalContainerView: View {
    @Environment(TerminalViewModel.self) var sshViewModel: TerminalViewModel?
    @Environment(LocalTerminalManager.self) var localManager: LocalTerminalManager?

    var body: some View {
        //桥接 NSViewRepresentable, 根据哪个非nil决定模式
    }
}
```

Implementation approach: Add a `mode` enum or optional parameters to distinguish SSH vs local. The NSViewRepresentable's `makeNSView` will:
- SSH mode: connect to existing PTY from `TerminalViewModel` (current behavior, unchanged)
- Local mode: create `Terminal` + `LocalProcess(shell: "/bin/zsh")`, call `process.start(delegate:)`, wire the process's output to `terminal.feed()` for rendering. SwiftTerm's `TerminalView` has native `LocalProcess` support — the `LocalProcess` object feeds bytes into the `Terminal` model, and `TerminalView` renders it.

The key difference: SSH mode writes user input to `TTYStdinWriter` (SSH channel), while local mode writes to `LocalProcess`'s stdin pipe. Both produce output that flows into `Terminal.feed()`.

#### `ServerSidebarView` — Add mode toggle

Add a `@Binding var sidebarMode: SidebarMode` where:

```swift
enum SidebarMode: String, CaseIterable {
    case ssh = "SSH Servers"
    case local = "Local Terminals"
}
```

The picker sits at the top of the sidebar. In local mode, the list shows `LocalTerminalManager.sessions` with add/rename/close actions.

#### `ContentView` — Route based on mode

```swift
switch sidebarMode {
case .ssh:
    // existing logic (server selection → connection states → detail tabs)
case .local:
    LocalTerminalView()
        .environment(localManager)
}
```

#### `LocalTerminalView` (new file: `ShellDeck/Views/Terminal/LocalTerminalView.swift`)

```swift
struct LocalTerminalView: View {
    @Environment(LocalTerminalManager.self) var manager

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar (custom or TabView)
            TabView(selection: $manager.activeSessionID) {
                ForEach(manager.sessions) { session in
                    TerminalContainerView(localSession: session)
                        .tabItem { Text(session.title) }
                        .tag(session.id)
                }
            }
            // Toolbar: + new tab
        }
        .toolbar {
            Button("+") { manager.createSession() }
        }
    }
}
```

### File Changes Summary

| File | Change |
|------|--------|
| `ShellDeck/Views/Terminal/LocalTerminalSession.swift` | **New** — session model |
| `ShellDeck/Services/LocalTerminalManager.swift` | **New** — session manager |
| `ShellDeck/Views/Terminal/LocalTerminalView.swift` | **New** — local terminal tab view |
| `ShellDeck/Views/Terminal/TerminalContainerView.swift` | **Modify** — support local process mode |
| `ShellDeck/Views/Sidebar/ServerSidebarView.swift` | **Modify** — add mode picker + local terminal list |
| `ShellDeck/ContentView.swift` | **Modify** — route between SSH and local modes |

## Data Flow

### SSH Mode (unchanged)
```
Sidebar → select Server → ServerConnection → TerminalViewModel → SSH PTY → SwiftTerm
```

### Local Mode (new)
```
Sidebar mode toggle → LocalTerminalManager.createSession()
  → LocalTerminalSession(title:)
  → LocalProcess(shell: "/bin/zsh")
  → session.start()
  → TerminalContainerView(localSession:)
  → SwiftTerm TerminalView ← LocalProcess stdin/stdout
```

### Tab Management
```
+ button → manager.createSession() → new tab appears
x button → manager.closeSession(id:) → process killed, tab removed
tab click → manager.activeSessionID = session.id → view switches
```

## Error Handling

- `LocalProcess` start failure: Show error in terminal view, allow retry
- Process exit: Mark session `isRunning = false`, show "(exited)" in tab title
- No special sandbox handling needed — local shell runs in app sandbox with user permissions

## Testing Strategy

1. Create local terminal → verify shell prompt appears
2. Type commands → verify output renders correctly
3. Create multiple tabs → verify independent sessions
4. Close tab → verify process is killed (no zombie)
5. Close all tabs → verify clean state
6. Switch between SSH and local modes → verify no cross-contamination
7. Ctrl+C in local terminal → verify signal handling works
8. Resize window → verify terminal reflows
