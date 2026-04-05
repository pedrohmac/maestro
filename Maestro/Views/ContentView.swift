import SwiftUI
import SwiftData
import MaestroCore

enum NavigationItem: Hashable {
    case missionControl
    case kanban
    case timeline
    case activity
    case chat
    case git
    case settings
    case help
}

// MARK: - Focused Values

private struct SelectedNavigationKey: FocusedValueKey {
    typealias Value = Binding<NavigationItem?>
}

extension FocusedValues {
    var selectedNavigation: Binding<NavigationItem?>? {
        get { self[SelectedNavigationKey.self] }
        set { self[SelectedNavigationKey.self] = newValue }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AgentOrchestrator.self) private var orchestrator
    @Environment(AppState.self) private var appState
    @Query(sort: \Project.createdDate, order: .reverse) private var projects: [Project]
    @State private var selectedProject: Project?
    @State private var selectedNav: NavigationItem? = .kanban
    @State private var showingNewProject = false
    @State private var activitySelectedRunId: String?
    @State private var showingNewTask = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    private var isMissionControlVisible: Bool {
        selectedNav == .missionControl || (selectedProject == nil && selectedNav != .help)
    }

    private var detailNavigationTitle: String {
        if isMissionControlVisible {
            return "Mission Control"
        }
        guard let project = selectedProject else {
            return selectedNav == .help ? "Help" : "Maestro"
        }
        switch selectedNav {
        case .kanban, nil: return project.name
        case .timeline: return "\(project.name) — Timeline"
        case .activity: return "\(project.name) — Activity"
        case .git: return "\(project.name) — Git"
        case .settings: return "Project Settings"
        case .help: return "Help"
        default: return project.name
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TrialBannerView()

            NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                projects: projects,
                selectedProject: $selectedProject,
                selectedNav: $selectedNav,
                showingNewProject: $showingNewProject
            )
        } detail: {
            ZStack {
                MissionControlView(isActive: isMissionControlVisible)
                    .opacity(isMissionControlVisible ? 1 : 0)
                    .allowsHitTesting(isMissionControlVisible)

                if let project = selectedProject {
                    KanbanBoardView(project: project, showToolbar: !isMissionControlVisible && selectedNav != .help, onNavigateToRun: { runId in
                        activitySelectedRunId = runId
                        selectedNav = .activity
                    }, onNavigateToSettings: {
                        selectedNav = .settings
                    })
                    .id(project.id)
                    .opacity(selectedNav == .kanban || selectedNav == nil ? 1 : 0)
                    .allowsHitTesting(selectedNav == .kanban || selectedNav == nil)

                    ProjectTimelineView(project: project)
                        .opacity(selectedNav == .timeline ? 1 : 0)
                        .allowsHitTesting(selectedNav == .timeline)

                    AgentActivityView(project: project, selectedRunId: $activitySelectedRunId)
                        .opacity(selectedNav == .activity ? 1 : 0)
                        .allowsHitTesting(selectedNav == .activity)

                    ChatView(project: project)
                        .opacity(selectedNav == .chat ? 1 : 0)
                        .allowsHitTesting(selectedNav == .chat)

                    GitIntegrationView(project: project)
                        .opacity(selectedNav == .git ? 1 : 0)
                        .allowsHitTesting(selectedNav == .git)

                    ProjectSettingsView(project: project)
                        .id(project.id)
                        .opacity(selectedNav == .settings ? 1 : 0)
                        .allowsHitTesting(selectedNav == .settings)
                }

                HelpView()
                    .opacity(selectedNav == .help ? 1 : 0)
                    .allowsHitTesting(selectedNav == .help)
            }
            .navigationTitle(detailNavigationTitle)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    if let project = selectedProject, !isMissionControlVisible, selectedNav != .help {
                        LaunchButton(project: project)
                    }
                }
            }
        }
        }
        .sheet(isPresented: $showingNewTask) {
            if let project = selectedProject {
                NewTaskSheet(project: project)
            }
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet { name, workspace in
                if !workspace.isEmpty {
                    let url = URL(fileURLWithPath: workspace)
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                }
                let project = Project(name: name, workspaceRoot: workspace)
                modelContext.insert(project)
                selectedProject = project
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.isShowingOnboarding },
            set: { appState.isShowingOnboarding = $0 }
        )) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .onAppear {
            if selectedProject == nil {
                selectedProject = projects.first
            }
            orchestrator.configure(modelContext: modelContext)
        }
        .frame(minWidth: 900, minHeight: 600)
        .focusedSceneValue(\.selectedNavigation, $selectedNav)
        .background {
            Group {
                Button("") { selectedNav = .missionControl }
                    .keyboardShortcut("0", modifiers: .command)
                Button("") { selectedNav = .kanban }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { selectedNav = .activity }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { selectedNav = .timeline }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { selectedNav = .chat }
                    .keyboardShortcut("4", modifiers: .command)
                Button("") { selectedNav = .git }
                    .keyboardShortcut("5", modifiers: .command)
                Button("") { selectedNav = .settings }
                    .keyboardShortcut("6", modifiers: .command)
                Button("") { if selectedProject != nil { showingNewTask = true } }
                    .keyboardShortcut("n", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }
}

struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var workspace = ""
    let onCreate: (String, String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("New Project")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("Project Name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                TextField("Workspace Path", text: $workspace)
                    .textFieldStyle(.roundedBorder)
                Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.canCreateDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        workspace = url.path
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Create") {
                    onCreate(name, workspace)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
