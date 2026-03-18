import SwiftUI
import SwiftData
import MaestroCore

struct TaskDetailView: View {
    @Bindable var task: ProjectTask
    var onDismiss: (() -> Void)? = nil
    var onNavigateToRun: ((String) -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.isDarkerMode) private var isDarkerMode
    @Environment(AgentOrchestrator.self) private var orchestrator
    @State private var showDeleteConfirmation = false
    @State private var newCommentText = ""
    @State private var rollbackTargetCommitId: String?
    @State private var showRollbackConfirmation = false
    @State private var rollbackError: String?
    @State private var showRollbackError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Close button
                if let onDismiss {
                    HStack {
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // Header
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Title", text: $task.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .textFieldStyle(.plain)

                    HStack {
                        Picker("Status", selection: Binding(
                            get: { task.status },
                            set: { newStatus in
                                task.status = newStatus
                                if let project = task.project,
                                   let column = project.columnForStatus(newStatus) {
                                    task.columnId = column.id
                                }
                            }
                        )) {
                            ForEach(TaskStatus.allCases) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Divider()

                // Properties
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Priority")
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        HStack(spacing: 6) {
                            ForEach(Priority.allCases) { p in
                                let color = priorityColor(for: p)
                                let isSelected = task.priority == p
                                Button {
                                    task.priority = p
                                } label: {
                                    Text(p.rawValue)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(color.opacity(isSelected ? 0.2 : 0.08), in: Capsule())
                                        .foregroundStyle(isSelected ? color : color.opacity(0.5))
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(isSelected ? color.opacity(0.4) : .clear, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack {
                        Text("Created")
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Text(task.createdDate, style: .date)
                    }

                    HStack {
                        Text("Start Date")
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        DatePicker("", selection: Binding(
                            get: { task.startDate ?? Date() },
                            set: { task.startDate = $0 }
                        ), displayedComponents: .date)
                        .labelsHidden()
                        if task.startDate != nil {
                            Button { task.startDate = nil } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        Text("Due Date")
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        DatePicker("", selection: Binding(
                            get: { task.dueDate ?? Date() },
                            set: { task.dueDate = $0 }
                        ), displayedComponents: .date)
                        .labelsHidden()
                        if task.dueDate != nil {
                            Button { task.dueDate = nil } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        Text("Worktree")
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Toggle("Use dedicated git worktree", isOn: $task.useWorktree)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }

                Divider()

                // Description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.headline)
                    TextEditor(text: $task.taskDescription)
                        .font(.body)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color.controlBackground(darker: isDarkerMode), in: RoundedRectangle(cornerRadius: 6))
                }

                Divider()

                // Discussion Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Discussion")
                        .font(.headline)

                    let sortedComments = (task.comments ?? []).sorted { $0.createdDate < $1.createdDate }
                    if sortedComments.isEmpty {
                        Text("No comments yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedComments, id: \.id) { comment in
                            TaskCommentRow(comment: comment, onNavigateToRun: onNavigateToRun)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Add a comment...", text: $newCommentText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addComment() }
                        Button(action: addComment) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                        .disabled(newCommentText.isEmpty)
                    }
                }

                Divider()

                // Commits Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Commits")
                        .font(.headline)

                    let sortedCommits = (task.commits ?? []).sorted { $0.authorDate > $1.authorDate }
                    if sortedCommits.isEmpty {
                        Text("No commits yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedCommits, id: \.id) { commit in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 5)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(commit.message)
                                        .font(.subheadline)
                                        .lineLimit(2)

                                    HStack(spacing: 6) {
                                        Text(commit.shortSha)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.blue)
                                            .textSelection(.enabled)

                                        Text("\u{00B7}")
                                            .foregroundStyle(.secondary)

                                        Text(commit.authorName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text("\u{00B7}")
                                            .foregroundStyle(.secondary)

                                        Text(commit.authorDate.relativeFormatted)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Button {
                                    rollbackTargetCommitId = commit.id
                                    showRollbackConfirmation = true
                                } label: {
                                    Label("Rollback", systemImage: "arrow.uturn.backward")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(.purple)
                            }
                        }
                    }
                }

                Divider()

                // Agent Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Agent")
                        .font(.headline)

                    // Pending Permissions
                    if let runner = orchestrator.getRunner(for: task.id) {
                        let pending = runner.pendingPermissions.filter {
                            if case .pending = $0.resolution { return true }
                            return false
                        }
                        if !pending.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: "lock.shield.fill")
                                        .foregroundStyle(.orange)
                                    Text("\(pending.count) pending permission\(pending.count == 1 ? "" : "s")")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.orange)
                                }

                                ForEach(pending) { perm in
                                    PermissionRequestCard(
                                        permission: perm,
                                        onAllow: {
                                            orchestrator.respondToPermission(taskId: task.id, requestId: perm.id, granted: true)
                                        },
                                        onDeny: {
                                            orchestrator.respondToPermission(taskId: task.id, requestId: perm.id, granted: false)
                                        }
                                    )
                                }
                            }
                            .padding(10)
                            .background(Color.orange.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    HStack {
                        if task.isAgentRunning {
                            Button(action: {
                                orchestrator.cancelAgent(taskId: task.id)
                            }) {
                                Label("Cancel Agent", systemImage: "stop.circle")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)

                            if let runId = task.latestRun?.id, let onNavigateToRun {
                                Button {
                                    onNavigateToRun(runId)
                                } label: {
                                    Label("View Activity", systemImage: "eye")
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                            }

                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button(action: {
                                if let project = task.project {
                                    orchestrator.runAgent(task: task, project: project)
                                }
                            }) {
                                Label("Run Agent", systemImage: "bolt.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(task.project?.workspaceRoot.isEmpty ?? true)

                            if let lastRun = task.latestRun, let sessionId = lastRun.sessionId {
                                Button(action: {
                                    if let project = task.project {
                                        orchestrator.resumeAgent(task: task, project: project, sessionId: sessionId)
                                    }
                                }) {
                                    Label("Resume", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    // Agent runs history
                    if let runs = task.agentRuns, !runs.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Run History")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            ForEach(runs.sorted(by: { $0.startedAt > $1.startedAt }), id: \.id) { run in
                                DisclosureGroup {
                                    ScrollView {
                                        Text(run.log.isEmpty ? "No output" : run.log)
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .frame(maxHeight: 200)
                                } label: {
                                    HStack {
                                        Image(systemName: run.status == .completed ? "checkmark.circle.fill" :
                                                run.status == .running ? "bolt.fill" :
                                                run.status == .failed ? "xmark.circle.fill" :
                                                run.status == .rolledBack ? "arrow.uturn.backward.circle" : "circle")
                                            .foregroundStyle(run.status == .completed ? .green :
                                                    run.status == .running ? .orange :
                                                    run.status == .failed ? .red :
                                                    run.status == .rolledBack ? .purple : .gray)
                                        Text(run.startedAt, style: .date)
                                            .font(.caption)
                                        Text("\u{00B7}")
                                        Text(run.durationFormatted)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Spacer()

                                        if let onNavigateToRun {
                                            Button {
                                                onNavigateToRun(run.id)
                                            } label: {
                                                Image(systemName: "arrow.right.circle")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Spacer()

                // Delete button
                Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                    Label("Delete Task", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .confirmationDialog("Delete this task?", isPresented: $showDeleteConfirmation) {
                    Button("Delete", role: .destructive) {
                        modelContext.delete(task)
                        onDismiss?()
                    }
                }
            }
            .padding()
        }
        .confirmationDialog(
            "Rollback this commit?",
            isPresented: $showRollbackConfirmation,
            titleVisibility: .visible
        ) {
            Button("Rollback", role: .destructive) {
                if let commitId = rollbackTargetCommitId,
                   let commit = task.commits?.first(where: { $0.id == commitId }) {
                    if let error = orchestrator.rollbackCommit(commit, task: task) {
                        rollbackError = error
                        showRollbackError = true
                    }
                }
                rollbackTargetCommitId = nil
            }
            Button("Cancel", role: .cancel) {
                rollbackTargetCommitId = nil
            }
        } message: {
            Text("This will reset the workspace to before this commit. This action cannot be undone.")
        }
        .alert("Rollback Failed", isPresented: $showRollbackError) {
            Button("OK") {}
        } message: {
            Text(rollbackError ?? "Unknown error")
        }
    }

    private func priorityColor(for priority: Priority) -> Color {
        switch priority {
        case .low: return Color(red: 0.74, green: 0.74, blue: 0.76)
        case .medium: return Color(red: 0.0, green: 0.63, blue: 1.0)
        case .high: return Color(red: 1.0, green: 0.77, blue: 0.0)
        case .critical: return Color(red: 1.0, green: 0.31, blue: 0.25)
        }
    }

    private func addComment() {
        guard !newCommentText.isEmpty else { return }
        let comment = TaskComment(body: newCommentText, authorType: .user, task: task)
        modelContext.insert(comment)
        newCommentText = ""
    }
}
