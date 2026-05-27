import SwiftUI
import SwiftData

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色模式"
        case .dark: return "深色模式"
        }
    }
    
    var icon: String {
        switch self {
        case .system: return "desktopcomputer"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@main
struct ShellDeckApp: App {
    @AppStorage("appTheme") private var appTheme: String = AppTheme.system.rawValue

    let container: ModelContainer = {
        let schema = Schema([Server.self, ServerGroup.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("无法初始化数据库: \(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
                .onAppear {
                    updateWindowAppearance(for: AppTheme(rawValue: appTheme) ?? .system)
                }
                .onChange(of: appTheme) { _, newValue in
                    updateWindowAppearance(for: AppTheme(rawValue: newValue) ?? .system)
                }
        }
        .modelContainer(container)
    }

    private func updateWindowAppearance(for theme: AppTheme) {
        DispatchQueue.main.async {
            for window in NSApp.windows {
                switch theme {
                case .system:
                    window.appearance = nil
                case .light:
                    window.appearance = NSAppearance(named: .aqua)
                case .dark:
                    window.appearance = NSAppearance(named: .darkAqua)
                }
            }
        }
    }
}
