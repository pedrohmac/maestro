import SwiftUI
import SwiftData
import MaestroCore

struct ProjectSettingsView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var modelContext
    @Environment(AgentOrchestrator.self) private var orchestrator
    @State private var showAllArchived = false
    @State private var claudeMDContent: String = ""
    @State private var savedClaudeMDContent: String = ""
    @State private var claudeMDFileExists: Bool = false
    @State private var saveError: String?
    @State private var showTemplateConfirmation: Bool = false
    @State private var showGenerateConfirmation: Bool = false
    @State private var isGitInitialized: Bool = false

    @State private var totalCostUSD: Double = 0

    private func refreshTotalCost() {
        let projectId = project.id
        let descriptor = FetchDescriptor<AgentRun>(
            predicate: #Predicate { $0.projectId == projectId }
        )
        let runs = (try? modelContext.fetch(descriptor)) ?? []
        totalCostUSD = runs.compactMap(\.costUSD).reduce(0, +)
    }

    var archivedTasks: [ProjectTask] {
        (project.tasks ?? [])
            .filter { $0.isArchived }
            .sorted { ($0.archivedDate ?? .distantPast) > ($1.archivedDate ?? .distantPast) }
    }

    private var claudeMDPath: String {
        "\(project.workspaceRoot)/CLAUDE.md"
    }

    private var isClaudeMDDirty: Bool {
        claudeMDContent != savedClaudeMDContent
    }

    private var showClaudeMDEditor: Bool {
        claudeMDFileExists || !claudeMDContent.isEmpty
    }

    private var hasValidWorkspace: Bool {
        !project.workspaceRoot.isEmpty &&
        FileManager.default.fileExists(atPath: project.workspaceRoot)
    }

    private var generation: ClaudeMDGeneration? {
        orchestrator.claudeMDGenerations[project.id]
    }

    private var isGenerating: Bool {
        generation?.isGenerating ?? false
    }

    private var generationError: String? {
        saveError ?? generation?.error
    }

    var body: some View {
        Form {
            Section("Project") {
                TextField("Name", text: $project.name)

                TextField("Description", text: $project.projectDescription, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Workspace") {
                HStack {
                    TextField("Root Path", text: $project.workspaceRoot)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            project.workspaceRoot = url.path
                        }
                    }
                }

                if hasValidWorkspace {
                    if isGitInitialized {
                        Label("Git repository initialized", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        HStack {
                            Label("Not a git repository", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Spacer()
                            Button("Initialize Git") {
                                initializeGit()
                            }
                            .controlSize(.small)
                        }
                    }
                }

                TextField("Default Branch", text: $project.defaultBranch, prompt: Text("e.g. main"))
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isGitInitialized)
                Text("The git branch agents will work on. Applies to all tickets in this project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Strategy", selection: Binding(
                    get: { project.workspaceStrategy },
                    set: { project.workspaceStrategy = $0 }
                )) {
                    ForEach(WorkspaceStrategy.allCases) { strategy in
                        Text(strategy.rawValue).tag(strategy)
                    }
                }
                .disabled(!isGitInitialized)

                switch project.workspaceStrategy {
                case .shared:
                    Text("All agents work directly in the project root. Simpler, but concurrent agents may conflict.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .isolated:
                    Text("Each task gets its own git worktree under .maestro-workspaces/, allowing safe parallel work.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Use worktree per task by default", isOn: $project.defaultUseWorktree)
                    .disabled(!isGitInitialized)
                Text("New tasks will default to using a dedicated git worktree and branch. Can be overridden per task.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Agent Configuration") {
                Picker("Dispatch Mode", selection: Binding(
                    get: { project.dispatchMode },
                    set: { project.dispatchMode = $0 }
                )) {
                    ForEach(DispatchMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                if project.dispatchMode == .auto {
                    Text("Tasks moved to 'In Progress' will automatically spawn an agent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Stepper("Max Concurrent Agents: \(project.maxConcurrentAgents)", value: $project.maxConcurrentAgents, in: 1...10)

                permissionRulesSection

                TextField("Allowed Tools", text: $project.defaultAllowedTools)
                    .textFieldStyle(.roundedBorder)
                Text("Comma-separated list: Bash,Read,Edit,Write,Glob,Grep")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Stepper("Max Turns: \(project.maxTurns)", value: $project.maxTurns, in: 1...100)
                Text("Maximum number of tool-use turns per agent session before it stops.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Max Budget (USD)")
                    TextField("", value: $project.maxBudgetUSD, format: .number, prompt: Text("Optional").font(.system(size: NSFont.systemFontSize * 0.7)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }

            Section("Usage") {
                HStack {
                    Text("Total Cost")
                    Spacer()
                    Text(String(format: "$%.2f", totalCostUSD))
                        .foregroundStyle(.secondary)
                }
            }

            Section("CLAUDE.md") {
                if !hasValidWorkspace {
                    Text("Set a workspace root path first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if showClaudeMDEditor {
                    TextEditor(text: $claudeMDContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

                    // Status line
                    Group {
                        if let error = generationError {
                            Text(error)
                                .foregroundStyle(.red)
                        } else if isGenerating {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Generating...")
                            }
                        } else if isClaudeMDDirty {
                            Text("Unsaved changes")
                                .foregroundStyle(.orange)
                        } else {
                            Text("Saved")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)

                    HStack {
                        Button("Save") {
                            saveClaudeMD()
                        }
                        .disabled(!isClaudeMDDirty || isGenerating)

                        Button("New from Template") {
                            if isClaudeMDDirty {
                                showTemplateConfirmation = true
                            } else {
                                applyTemplate()
                            }
                        }
                        .disabled(isGenerating)

                        Button {
                            if isGenerating {
                                orchestrator.cancelClaudeMDGeneration(projectId: project.id)
                            } else if isClaudeMDDirty {
                                showGenerateConfirmation = true
                            } else {
                                generateClaudeMD()
                            }
                        } label: {
                            if isGenerating {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Generating...")
                                }
                            } else {
                                Text("Generate with Claude")
                            }
                        }
                    }

                    Text("This file is read automatically by Claude agents working in this project's workspace.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No CLAUDE.md found in workspace. This file gives agents instant context about your project so they skip exploration and start working immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let error = generationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        Button("New from Template") {
                            applyTemplate()
                        }
                        .disabled(isGenerating)

                        Button {
                            generateClaudeMD()
                        } label: {
                            if isGenerating {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Generating...")
                                }
                            } else {
                                Text("Generate with Claude")
                            }
                        }
                        .disabled(isGenerating)
                    }
                }
            }

            Section("Workflow Prompt") {
                TextEditor(text: $project.workflowPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

                Text("Appended as system instructions to every agent session in this project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Archived Tasks") {
                if archivedTasks.isEmpty {
                    Text("No archived tasks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let visibleTasks = showAllArchived ? archivedTasks : Array(archivedTasks.prefix(5))
                    let hiddenCount = archivedTasks.count - 5

                    Text("\(archivedTasks.count) archived task\(archivedTasks.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(visibleTasks, id: \.id) { task in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.body)
                                    .lineLimit(1)

                                HStack(spacing: 8) {
                                    Text(task.priority.rawValue)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(archivedPriorityColor(for: task.priority).opacity(0.15), in: Capsule())
                                        .foregroundStyle(archivedPriorityColor(for: task.priority))

                                    if let archivedDate = task.archivedDate {
                                        Text("Archived \(archivedDate, style: .date)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            Button {
                                task.isArchived = false
                                task.archivedDate = nil
                                task.status = .done
                                try? modelContext.save()
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Restore to board")

                            Button(role: .destructive) {
                                modelContext.delete(task)
                                try? modelContext.save()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Delete permanently")
                        }
                    }

                    if hiddenCount > 0 {
                        Button {
                            withAnimation {
                                showAllArchived.toggle()
                            }
                        } label: {
                            Text(showAllArchived ? "Show Less" : "Show \(hiddenCount) More...")
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Project Settings")
        .onAppear {
            loadClaudeMD()
            checkGitStatus()
            refreshTotalCost()
            // Pick up result from background generation that completed while away
            if let gen = generation, !gen.isGenerating {
                if let result = gen.result {
                    claudeMDContent = result
                }
                orchestrator.clearClaudeMDGeneration(projectId: project.id)
            }
        }
        .onChange(of: project.workspaceRoot) {
            checkGitStatus()
        }
        .onChange(of: project.id) {
            refreshTotalCost()
        }
        .onChange(of: generation?.isGenerating) {
            // Apply result when generation completes while view is visible
            if let gen = generation, !gen.isGenerating {
                if let result = gen.result {
                    claudeMDContent = result
                }
                orchestrator.clearClaudeMDGeneration(projectId: project.id)
            }
        }
        .alert("Replace unsaved changes with template?", isPresented: $showTemplateConfirmation) {
            Button("Replace", role: .destructive) { applyTemplate() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Replace unsaved changes? Claude will generate new content.", isPresented: $showGenerateConfirmation) {
            Button("Replace", role: .destructive) { generateClaudeMD() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func checkGitStatus() {
        guard hasValidWorkspace else {
            isGitInitialized = false
            return
        }
        let gitDir = URL(fileURLWithPath: project.workspaceRoot)
            .appendingPathComponent(".git").path
        isGitInitialized = FileManager.default.fileExists(atPath: gitDir)
    }

    private func initializeGit() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = URL(fileURLWithPath: project.workspaceRoot)
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        checkGitStatus()
    }

    private func loadClaudeMD() {
        let path = claudeMDPath
        if FileManager.default.fileExists(atPath: path),
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            claudeMDContent = content
            savedClaudeMDContent = content
            claudeMDFileExists = true
        } else {
            claudeMDFileExists = false
        }
    }

    private func saveClaudeMD() {
        do {
            try claudeMDContent.write(toFile: claudeMDPath, atomically: true, encoding: .utf8)
            savedClaudeMDContent = claudeMDContent
            claudeMDFileExists = true
            saveError = nil
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func applyTemplate() {
        claudeMDContent = """
        # \(project.name)

        [Brief description of what this project does]

        ## Tech Stack

        - ...

        ## Project Structure

        [Key directories and what lives where]

        ## Build Commands

        ```sh
        # How to build
        # How to test
        ```

        ## Key Architecture Decisions

        - ...

        ## Conventions

        - ...
        """
        saveError = nil
    }

    private func generateClaudeMD() {
        orchestrator.generateClaudeMD(projectId: project.id, workspacePath: project.workspaceRoot)
    }

    private static let knownTools = ["Bash", "Read", "Edit", "Write", "Glob", "Grep", "*"]

    @ViewBuilder
    private var permissionRulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permission Rules")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("Rules evaluated in order, first match wins. Unmatched requests require manual approval in the task sidebar.")
                .font(.caption)
                .foregroundStyle(.secondary)

            let rules = project.permissionRules
            if !rules.isEmpty {
                ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                    HStack(spacing: 8) {
                        // Reorder buttons
                        VStack(spacing: 0) {
                            Button {
                                moveRule(at: index, direction: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .disabled(index == 0)

                            Button {
                                moveRule(at: index, direction: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .disabled(index == rules.count - 1)
                        }
                        .foregroundStyle(.secondary)

                        // Tool name
                        Picker("", selection: Binding(
                            get: {
                                Self.knownTools.contains(rule.toolName) ? rule.toolName : "custom"
                            },
                            set: { newValue in
                                var updated = project.permissionRules
                                if newValue != "custom" {
                                    updated[index].toolName = newValue
                                }
                                project.permissionRules = updated
                            }
                        )) {
                            ForEach(Self.knownTools, id: \.self) { tool in
                                Text(tool == "*" ? "Any (*)" : tool).tag(tool)
                            }
                            Text("Custom").tag("custom")
                        }
                        .frame(width: 100)

                        if !Self.knownTools.contains(rule.toolName) {
                            TextField("Tool", text: Binding(
                                get: { rule.toolName },
                                set: { newValue in
                                    var updated = project.permissionRules
                                    updated[index].toolName = newValue
                                    project.permissionRules = updated
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        }

                        // Action
                        Picker("", selection: Binding(
                            get: { rule.action },
                            set: { newValue in
                                var updated = project.permissionRules
                                updated[index].action = newValue
                                project.permissionRules = updated
                            }
                        )) {
                            ForEach(RuleAction.allCases) { action in
                                Text(action.rawValue).tag(action)
                            }
                        }
                        .frame(width: 80)

                        // Path pattern
                        TextField("Path pattern (optional)", text: Binding(
                            get: { rule.pathPattern ?? "" },
                            set: { newValue in
                                var updated = project.permissionRules
                                updated[index].pathPattern = newValue.isEmpty ? nil : newValue
                                project.permissionRules = updated
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))

                        // Delete
                        Button {
                            var updated = project.permissionRules
                            updated.remove(at: index)
                            project.permissionRules = updated
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                var updated = project.permissionRules
                updated.append(PermissionRule(toolName: "Bash", action: .allow))
                project.permissionRules = updated
            } label: {
                Label("Add Rule", systemImage: "plus.circle")
            }
            .controlSize(.small)
        }
    }

    private func moveRule(at index: Int, direction: Int) {
        var rules = project.permissionRules
        let newIndex = index + direction
        guard newIndex >= 0 && newIndex < rules.count else { return }
        rules.swapAt(index, newIndex)
        project.permissionRules = rules
    }

    private func archivedPriorityColor(for priority: Priority) -> Color {
        switch priority {
        case .low: return Color(red: 0.74, green: 0.74, blue: 0.76)
        case .medium: return Color(red: 0.0, green: 0.63, blue: 1.0)
        case .high: return Color(red: 1.0, green: 0.77, blue: 0.0)
        case .critical: return Color(red: 1.0, green: 0.31, blue: 0.25)
        }
    }
}
