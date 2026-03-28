import SwiftUI
import SwiftData
import MaestroCore

@main
struct MaestroApp: App {
    let modelContainer: ModelContainer
    @State private var orchestrator = AgentOrchestrator()
    @State private var appState = AppState()
    @State private var launcher = ProjectLauncher()
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
                .environment(appState)
                .environment(launcher)
                .environment(\.isDarkerMode, currentMode.isDarker)
                .preferredColorScheme(colorScheme)
                .task {
                    orchestrator.appState = appState
                    await appState.validateOnLaunch()
                }
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environment(orchestrator)
                .environment(appState)
                .modelContainer(modelContainer)
                .environment(\.isDarkerMode, currentMode.isDarker)
                .preferredColorScheme(colorScheme)
        }
    }
}
