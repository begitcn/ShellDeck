import SwiftUI

enum ToastLevel {
    case info, success, warning, error

    var color: Color {
        switch self {
        case .info: .accentColor
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    var icon: String {
        switch self {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        }
    }
}

struct ToastItem: Identifiable {
    let id = UUID()
    let message: String
    let level: ToastLevel
}

@MainActor
@Observable
final class ToastManager {
    static let shared = ToastManager()
    private(set) var items: [ToastItem] = []

    private init() {}

    func show(_ message: String, level: ToastLevel = .info) {
        let item = ToastItem(message: message, level: level)
        items.append(item)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            await MainActor.run {
                self?.dismiss(item.id)
            }
        }
    }

    func dismiss(_ id: UUID) {
        items.removeAll { $0.id == id }
    }
}

struct ToastModifier: ViewModifier {
    @State private var manager = ToastManager.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if !manager.items.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(manager.items) { item in
                            ToastRow(item: item)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.top, 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: manager.items.count)
                }
            }
    }
}

struct ToastRow: View {
    let item: ToastItem
    @State private var offset: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.level.icon)
                .foregroundStyle(item.level.color)
                .font(.body)
            Text(item.message)
                .font(.system(size: SDFontSize.body.value))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                ToastManager.shared.dismiss(item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SDSpacing.lg.value)
        .padding(.vertical, SDSpacing.md.value)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(item.level.color.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        .padding(.horizontal, SDSpacing.xxl.value)
        .offset(y: offset)
        .onAppear {
            offset = -20
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                offset = 0
            }
        }
    }
}

extension View {
    func withToast() -> some View {
        modifier(ToastModifier())
    }
}
