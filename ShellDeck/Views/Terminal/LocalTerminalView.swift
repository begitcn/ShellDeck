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

    private var activeSessionBinding: Binding<UUID?> {
        Binding(
            get: { manager.activeSessionID },
            set: { manager.activeSessionID = $0 }
        )
    }

    private var tabView: some View {
        TabView(selection: activeSessionBinding) {
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
