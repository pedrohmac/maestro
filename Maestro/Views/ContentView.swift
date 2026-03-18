import SwiftUI
import SwiftData
import MaestroCore

enum NavigationItem: Hashable {
    case kanban
    case gantt
    case activity
    case chat
    case git
    case settings
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AgentOrchestrator.self) private var orchestrator
    @Query(sort: \Project.createdDate, order: .reverse) private var projects: [Project]
    @State private var selectedProject: Project?
    @State private var selectedNav: NavigationItem? = .kanban
    @State private var showingNewProject = false
    @State private var activitySelectedRunId: String?
    @State private var showingNewTask = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                projects: projects,
                selectedProject: $selectedProject,
                selectedNav: $selectedNav,
                showingNewProject: $showingNewProject
            )
        } detail: {
            Group {
                if let project = selectedProject {
                    ZStack {
                        KanbanBoardView(project: project, onNavigateToRun: { runId in
                            activitySelectedRunId = runId
                            selectedNav = .activity
                        }, onNavigateToSettings: {
                            selectedNav = .settings
                        })
                        .id(project.id)
                        .opacity(selectedNav == .kanban || selectedNav == nil ? 1 : 0)
                        .allowsHitTesting(selectedNav == .kanban || selectedNav == nil)

                        GanttChartView(project: project)
                            .opacity(selectedNav == .gantt ? 1 : 0)
                            .allowsHitTesting(selectedNav == .gantt)

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
                } else {
                    ContentUnavailableView("No Project Selected", systemImage: "folder", description: Text("Select a project from the sidebar or create a new one."))
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
                let project = Project(name: name, workspaceRoot: workspace)
                modelContext.insert(project)
                selectedProject = project
            }
        }
        .onAppear {
            if selectedProject == nil {
                selectedProject = projects.first
            }
            orchestrator.configure(modelContext: modelContext)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background {
            Group {
                Button("") { selectedNav = .kanban }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { selectedNav = .activity }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { selectedNav = .gantt }
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
