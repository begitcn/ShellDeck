import SwiftUI

struct LocalTerminalView: View {
    @Environment(LocalTerminalManager.self) var manager

    var body: some View {
        ZStack {
            if manager.sessions.isEmpty {
                emptyView
            } else {
                TerminalHostView(activeSessionID: manager.activeSessionID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !manager.sessions.isEmpty {
                bottomBar
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.purple)
                .frame(width: 5, height: 5)
            Text("本地")
                .font(.caption2)
                .foregroundStyle(.purple)
            if let active = manager.sessions.first(where: { $0.id == manager.activeSessionID }) {
                Text("\(active.shellType) · \(active.workingDirectory)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("◈ 80×24")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
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
}
