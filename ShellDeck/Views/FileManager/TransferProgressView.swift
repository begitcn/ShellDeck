import SwiftUI

struct TransferProgressView: View {
    let tasks: [TransferTask]
    let onDismissCompleted: () -> Void
    let onDismissTask: (TransferTask) -> Void

    @State private var isExpanded = false

    private var activeTasks: [TransferTask] {
        tasks.filter { task in
            if case .completed = task.status { return false }
            if case .failed = task.status { return false }
            return true
        }
    }

    private var hasActiveTasks: Bool { !activeTasks.isEmpty }

    private var completedTasks: [TransferTask] {
        tasks.filter { task in
            if case .completed = task.status { return true }
            if case .failed = task.status { return true }
            return false
        }
    }

    var body: some View {
        if tasks.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                Divider()
                VStack(spacing: 6) {
                    header
                    if isExpanded {
                        ForEach(tasks) { task in
                            taskRow(task)
                        }
                        if !completedTasks.isEmpty {
                            dismissButton
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .onChange(of: activeTasks.count) { _, count in
                if count > 0 { isExpanded = true }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("传输任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if activeTasks.isEmpty {
                    Text("(\(completedTasks.count) 个已完成)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("(\(activeTasks.count) 个进行中)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if !activeTasks.isEmpty {
                    SpinningIndicator()
                        .frame(width: 12, height: 12)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func taskRow(_ task: TransferTask) -> some View {
        HStack(spacing: 8) {
            Image(systemName: task.type.icon)
                .font(.caption)
                .foregroundStyle(taskStatusColor(task.status))

            VStack(spacing: 2) {
                HStack {
                    Text(task.fileName)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    switch task.status {
                    case .pending:
                        Text("等待中")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    case .transferring:
                        HStack(spacing: 4) {
                            Text(task.speedFormatted)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(task.progressFormatted)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    case .completed:
                        Text("完成")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    case .failed(let error):
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }

                ProgressView(value: task.progress)
                    .progressViewStyle(.linear)
                    .tint(taskStatusColor(task.status))
                    .frame(height: 6)
            }

            if !isActive(task.status) {
                Button {
                    onDismissTask(task)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 14)
    }

    private var dismissButton: some View {
        HStack {
            Spacer()
            Button("清除已完成", action: onDismissCompleted)
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 14)
    }

    private func isActive(_ status: TransferStatus) -> Bool {
        switch status {
        case .pending, .transferring: return true
        case .completed, .failed: return false
        }
    }

    private func taskStatusColor(_ status: TransferStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .transferring: return .accentColor
        case .completed: return .green
        case .failed: return .red
        }
    }
}

private struct SpinningIndicator: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.016, paused: false)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1) * 360
            Circle()
                .trim(from: 0, to: 0.8)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.accentColor, .accentColor.opacity(0.2)]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(angle))
        }
    }
}
