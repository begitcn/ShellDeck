import SwiftUI
import SwiftData

@main
struct ShellDeckApp: App {
    let container: ModelContainer = {
        let schema = Schema([Server.self])
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
        }
        .modelContainer(container)
    }
}
