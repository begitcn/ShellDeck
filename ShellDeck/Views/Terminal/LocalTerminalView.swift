import SwiftUI

struct LocalTerminalView: View {
    @Environment(LocalTerminalManager.self) var manager

    var body: some View {
        Group {
            if manager.sessions.isEmpty {
                emptyView
            } else {
                ZStack {
                    ForEach(manager.sessions) { session in
                        terminalTab(session: session)
                            .opacity(session.id == manager.activeSessionID ? 1.0 : 0.0)
                            .disabled(session.id != manager.activeSessionID)
                            .allowsHitTesting(session.id == manager.activeSessionID)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .symbolEffect(.bounce, value: manager.sessions.isEmpty)
            
            Text("没有打开的终端")
                .font(.title2)
                .bold()
                .foregroundStyle(.primary)
            
            Text("可以点击左下角或顶部的 + 按钮，或者点击下方按钮新建本地终端。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: {
                manager.createSession()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("新建本地终端")
                }
                .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.blue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func terminalTab(session: LocalTerminalSession) -> some View {
        LocalTerminalContainerView(
            session: session,
            isRunning: Binding(
                get: { session.isRunning },
                set: { session.isRunning = $0 }
            ),
            isActive: session.id == manager.activeSessionID
        )
    }
}
