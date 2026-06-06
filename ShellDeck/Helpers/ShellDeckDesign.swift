import SwiftUI

// MARK: - Design Tokens

enum SDSpacing: CGFloat {
    case xs = 4
    case sm = 8
    case md = 12
    case lg = 16
    case xl = 20
    case xxl = 24

    var value: CGFloat { rawValue }
}

enum SDFontSize: CGFloat {
    case caption = 11
    case body = 13
    case heading = 15
    case headline = 16
    case title2 = 20
    case title = 24
    case largeTitle = 28

    var value: CGFloat { rawValue }
}

enum SDFontWeight {
    case regular, medium, semibold, bold

    var value: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

extension Color {
    static let sdBrand = Color.accentColor
    static let sdSuccess = Color.green
    static let sdWarning = Color.orange
    static let sdDanger = Color.red
    static let sdInfo = Color.blue

    static let sdTextPrimary = Color.primary
    static let sdTextSecondary = Color.secondary
    static let sdTextTertiary = Color.gray.opacity(0.5)

    static let sdBackground = Color(nsColor: .windowBackgroundColor)
    static let sdSurface = Color.primary.opacity(0.06)
    static let sdSurfaceElevated = Color.primary.opacity(0.02)
    static let sdBorder = Color.primary.opacity(0.1)
}

// MARK: - Reusable Button Styles

struct SDPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: SDFontSize.body.value, weight: .medium))
            .foregroundStyle(.white)
            .frame(height: 36)
            .padding(.horizontal, SDSpacing.lg.value)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SDSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: SDFontSize.body.value))
            .foregroundStyle(.secondary)
            .frame(height: 32)
            .padding(.horizontal, SDSpacing.md.value)
            .background(configuration.isPressed ? Color.sdSurface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.sdBorder, lineWidth: 1)
            )
    }
}

struct SDGhostButtonStyle: ButtonStyle {
    var color: Color = .sdDanger

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: SDFontSize.body.value))
            .foregroundStyle(color.opacity(configuration.isPressed ? 0.7 : 1))
            .contentShape(Rectangle())
    }
}

// MARK: - Card Style

struct SDCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(SDSpacing.xl.value)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func sdCardStyle() -> some View {
        modifier(SDCardStyle())
    }
}

// MARK: - Section Header

struct SDSectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: SDSpacing.xs.value) {
            Text(title)
                .font(.system(size: SDFontSize.heading.value, weight: .semibold))
                .foregroundStyle(.primary)
            if let count {
                Text("\(count)")
                    .font(.system(size: SDFontSize.caption.value))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor)
                .frame(width: 2.5)
                .padding(.vertical, 4)
        }
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
    }
}
