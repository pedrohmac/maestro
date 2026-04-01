import SwiftUI

struct HelpView: View {
    @State private var selectedTopic: HelpTopic? = .gettingStarted

    var body: some View {
        HSplitView {
            List(HelpTopic.allCases, selection: $selectedTopic) { topic in
                Label(topic.title, systemImage: topic.icon)
                    .tag(topic)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)

            Group {
                if let topic = selectedTopic {
                    ScrollView {
                        topic.content
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(24)
                    }
                } else {
                    ContentUnavailableView("Select a Topic", systemImage: "questionmark.circle", description: Text("Choose a help topic from the list."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Help Topics

private enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted
    case projects
    case tasks
    case agents
    case keyboardShortcuts
    case troubleshooting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: "Getting Started"
        case .projects: "Projects"
        case .tasks: "Tasks"
        case .agents: "Agents"
        case .keyboardShortcuts: "Keyboard Shortcuts"
        case .troubleshooting: "Troubleshooting"
        }
    }

    var icon: String {
        switch self {
        case .gettingStarted: "play.circle"
        case .projects: "folder"
        case .tasks: "checklist"
        case .agents: "bolt.circle"
        case .keyboardShortcuts: "command"
        case .troubleshooting: "wrench.and.screwdriver"
        }
    }

    @ViewBuilder
    var content: some View {
        switch self {
        case .gettingStarted: GettingStartedContent()
        case .projects: ProjectsContent()
        case .tasks: TasksContent()
        case .agents: AgentsContent()
        case .keyboardShortcuts: KeyboardShortcutsContent()
        case .troubleshooting: TroubleshootingContent()
        }
    }
}

// MARK: - Getting Started

private struct GettingStartedContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HelpHeader(title: "Getting Started", subtitle: "Learn the basics of using Maestro to manage your projects with AI agents.")

            HelpStep(number: 1, title: "Configure Claude CLI", description: "Go to Settings (Cmd+,) > General and click Detect to find your Claude CLI installation. Maestro uses Claude CLI as its AI engine.")

            HelpStep(number: 2, title: "Create a Project", description: "Click the + button in the sidebar to create a new project. Point it at a folder on your Mac — ideally an empty git repository.")

            HelpStep(number: 3, title: "Add Tasks", description: "Press Cmd+N to create a task. Describe what you want built in detail — the more specific you are, the better the results.")

            HelpStep(number: 4, title: "Run an Agent", description: "Select a task on the Kanban board and click Run Agent. Switch to Activity (Cmd+2) to watch the agent work in real time.")

            HelpStep(number: 5, title: "Review the Results", description: "When the agent finishes, your task moves to the Review column. Check the files it created, then move the task to Done if you're satisfied.")
        }
    }
}

// MARK: - Projects

private struct ProjectsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HelpHeader(title: "Projects", subtitle: "A project in Maestro is a folder on your Mac where AI agents write code.")

            HelpSection(title: "Creating a Project") {
                Text("Click the + button in the sidebar, enter a name, and browse to a folder. The folder should ideally be a git repository so Maestro can track changes.")
            }

            HelpSection(title: "Workspace Strategy") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose how agents interact with your project files:")
                    HelpBullet(label: "Shared", text: "All tasks work directly in the project folder. Simpler, best for running one task at a time.")
                    HelpBullet(label: "Isolated", text: "Each task gets its own git worktree. Lets multiple agents work simultaneously without conflicts.")
                }
            }

            HelpSection(title: "Dispatch Modes") {
                VStack(alignment: .leading, spacing: 8) {
                    HelpBullet(label: "Manual", text: "You click Run Agent to start each task.")
                    HelpBullet(label: "Auto", text: "Agents start automatically when a task moves to In Progress.")
                }
            }

            HelpSection(title: "Project Settings") {
                Text("Select a project and press Cmd+6 to configure its workspace root, default branch, agent limits, CLAUDE.md instructions, and more.")
            }
        }
    }
}

// MARK: - Tasks

private struct TasksContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HelpHeader(title: "Tasks", subtitle: "Tasks are instructions that tell AI agents what to build.")

            HelpSection(title: "Task Status Flow") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tasks move through four stages on the Kanban board:")
                    HelpBullet(label: "Todo", text: "Waiting to be started.")
                    HelpBullet(label: "In Progress", text: "An agent is currently working on it.")
                    HelpBullet(label: "Review", text: "The agent finished — check the results.")
                    HelpBullet(label: "Done", text: "Completed and accepted.")
                }
            }

            HelpSection(title: "Writing Good Descriptions") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The quality of the agent's output depends on your description. Be specific about:")
                    HelpBullet(text: "What to build and how it should look")
                    HelpBullet(text: "Which technologies or frameworks to use")
                    HelpBullet(text: "Specific requirements like responsive design or color scheme")
                    HelpBullet(text: "File structure or naming conventions")
                }
            }

            HelpSection(title: "Tips") {
                VStack(alignment: .leading, spacing: 8) {
                    HelpBullet(text: "Break big projects into small, focused tasks for better results.")
                    HelpBullet(text: "Use the Workflow Prompt in Project Settings for instructions that apply to every task.")
                    HelpBullet(text: "Set a budget limit per task while you're learning.")
                }
            }
        }
    }
}

// MARK: - Agents

private struct AgentsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HelpHeader(title: "Agents", subtitle: "Agents are AI-powered workers that execute your tasks using Claude CLI.")

            HelpSection(title: "Running an Agent") {
                Text("Select a task on the Kanban board and click Run Agent in the detail panel. The agent reads your task description, plans its approach, writes code, and reports back when done.")
            }

            HelpSection(title: "Watching Progress") {
                Text("Switch to Agent Activity (Cmd+2) to see what the agent is doing in real time. You can see the tools it's using, files it's creating, and commands it's running.")
            }

            HelpSection(title: "Sending Messages") {
                Text("While an agent is running, you can send follow-up messages to guide it. Use the Agent Chat view (Cmd+4) or the input field in the Activity view to communicate with a running agent.")
            }

            HelpSection(title: "Concurrent Agents") {
                Text("You can run multiple agents simultaneously on different tasks. Configure the maximum number of concurrent agents in Project Settings. When using isolated workspace strategy, each agent gets its own git worktree to avoid conflicts.")
            }

            HelpSection(title: "Resuming Work") {
                Text("If an agent is interrupted or you want it to continue, click Resume instead of Run. This picks up the same session where it left off.")
            }
        }
    }
}

// MARK: - Keyboard Shortcuts

private struct KeyboardShortcutsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HelpHeader(title: "Keyboard Shortcuts", subtitle: "Navigate Maestro quickly with these shortcuts.")

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                shortcutRow("Cmd+1", "Kanban Board")
                shortcutRow("Cmd+2", "Agent Activity")
                shortcutRow("Cmd+3", "Gantt Chart")
                shortcutRow("Cmd+4", "Agent Chat")
                shortcutRow("Cmd+5", "Git")
                shortcutRow("Cmd+6", "Project Settings")
                shortcutRow("Cmd+7", "Help")
                Divider()
                    .gridCellColumns(2)
                shortcutRow("Cmd+N", "New Task")
                shortcutRow("Cmd+,", "App Settings")
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func shortcutRow(_ shortcut: String, _ action: String) -> some View {
        GridRow {
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(action)
        }
    }
}

// MARK: - Troubleshooting

private struct TroubleshootingContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HelpHeader(title: "Troubleshooting", subtitle: "Common issues and how to fix them.")

            HelpSection(title: "Claude CLI Not Found") {
                Text("Go to Settings (Cmd+,) > General and click Detect. If it's not found, click Browse and select the claude binary manually. You can find it by running \"which claude\" in Terminal.")
            }

            HelpSection(title: "Agent Seems Stuck") {
                Text("Click Cancel Agent and try again with a clearer, more specific task description. Breaking large tasks into smaller ones often helps.")
            }

            HelpSection(title: "Agent Not Writing Files") {
                Text("Make sure the Workspace Root in Project Settings points to a valid directory. If using isolated workspaces, ensure git is initialized in the project folder.")
            }

            HelpSection(title: "Connection Errors") {
                Text("Check that you are logged in to Claude CLI by running \"claude login\" in Terminal. Verify your internet connection is active.")
            }

            HelpSection(title: "Build Issues") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("If building from source:")
                    HelpBullet(text: "Make sure Xcode 16+ and XcodeGen are installed.")
                    HelpBullet(text: "Run \"xcodegen generate\" before building.")
                    HelpBullet(text: "Dependencies download automatically on first build — try building again if you see module errors.")
                }
            }
        }
    }
}

// MARK: - Reusable Components

private struct HelpHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title)
                .fontWeight(.bold)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }
}

private struct HelpSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
                .foregroundStyle(.secondary)
        }
    }
}

private struct HelpStep: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct HelpBullet: View {
    var label: String?
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
                .foregroundStyle(.tertiary)
            if let label {
                Text(label).fontWeight(.medium) + Text(" — \(text)")
            } else {
                Text(text)
            }
        }
    }
}
