import SwiftUI
import SwiftData

enum AppTheme: String, CaseIterable, Identifiable {
    case light = "light"
    case dark = "dark"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .light: return "浅色模式"
        case .dark: return "深色模式"
        }
    }
    
    var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@main
struct ShellDeckApp: App {
    @AppStorage("appTheme") private var appTheme: String = AppTheme.dark.rawValue

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
                    updateWindowAppearance(for: AppTheme(rawValue: appTheme) ?? .dark)
                    Task {
                        await UpdateService.shared.checkForUpdates(manual: false)
                    }
                }
                .onChange(of: appTheme) { _, newValue in
                    updateWindowAppearance(for: AppTheme(rawValue: newValue) ?? .dark)
                }
        }
        .modelContainer(container)
    }

    private func updateWindowAppearance(for theme: AppTheme) {
        DispatchQueue.main.async {
            for window in NSApp.windows {
                switch theme {
                case .light:
                    window.appearance = NSAppearance(named: .aqua)
                case .dark:
                    window.appearance = NSAppearance(named: .darkAqua)
                }
            }
        }
    }
}
