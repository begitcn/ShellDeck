import SwiftUI

struct LocalTerminalView: View {
    @Environment(LocalTerminalManager.self) var manager

    var body: some View {
        VStack(spacing: 0) {
            if manager.sessions.count >= 2 {
                tabBar
                Divider()
            }
            Group {
                if manager.sessions.isEmpty {
                    emptyView
                } else {
                    ZStack {
                        ForEach(manager.sessions) { session in
                            LocalTerminalContainerView(
                                session: session,
                                isRunning: Binding(
                                    get: { session.isRunning },
                                    set: { session.isRunning = $0 }
                                ),
                                isActive: session.id == manager.activeSessionID
                            )
                            .opacity(session.id == manager.activeSessionID ? 1.0 : 0.0)
                            .disabled(session.id != manager.activeSessionID)
                            .allowsHitTesting(session.id == manager.activeSessionID)
                        }
                    }
                }
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

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(manager.sessions) { session in
                    Button {
                        manager.activeSessionID = session.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal")
                                .font(.caption2)
                            Text(session.title)
                                .font(.caption2)
                                .fontWeight(session.id == manager.activeSessionID ? .semibold : .regular)
                            if manager.sessions.count > 1 {
                                Button {
                                    withAnimation { manager.closeSession(id: session.id) }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(.tertiary)
                                        .padding(1)
                                }
                                .buttonStyle(.plain)
                                .help("关闭")
                            }
                        }
                        .foregroundStyle(session.id == manager.activeSessionID ? .primary : .tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(
                            session.id == manager.activeSessionID
                                ? AnyShapeStyle(.ultraThinMaterial)
                                : AnyShapeStyle(Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color.black.opacity(0.35))
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
