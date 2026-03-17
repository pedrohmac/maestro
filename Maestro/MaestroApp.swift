import SwiftUI
import SwiftData
import MaestroCore

@main
struct MaestroApp: App {
    let modelContainer: ModelContainer
    @State private var orchestrator = AgentOrchestrator()
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue

    private var currentMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceMode) ?? .system
    }

    private var colorScheme: ColorScheme? {
        currentMode.colorScheme
    }

    init() {
        do {
            modelContainer = try MaestroStore.makeContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(orchestrator)
                .environment(\.isDarkerMode, currentMode.isDarker)
                .preferredColorScheme(colorScheme)
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environment(orchestrator)
                .modelContainer(modelContainer)
                .environment(\.isDarkerMode, currentMode.isDarker)
                .preferredColorScheme(colorScheme)
        }
    }
}
