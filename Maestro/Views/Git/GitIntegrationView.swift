import SwiftUI
import SwiftData
import MaestroCore

struct GitIntegrationView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var modelContext
    @Environment(\.isDarkerMode) private var isDarkerMode
    @State private var branches: [GitBranchInfo] = []
    @State private var selectedBranch: String?
    @State private var isLoading = false
    @State private var lastRefresh: Date?

    private var baseBranch: String {
        project.defaultBranch.isEmpty ? "main" : project.defaultBranch
    }

    var body: some View {
        NavigationSplitView {
            branchListSidebar
        } detail: {
            if let branchName = selectedBranch,
               let branch = branches.first(where: { $0.name == branchName }) {
                GitBranchDetailView(
                    branch: branch,
                    project: project,
                    baseBranch: baseBranch,
                    onRefresh: refreshBranches
                )
            } else {
                ContentUnavailableView(
                    "Select a Branch",
                    systemImage: "arrow.triangle.branch",
                    description: Text("Select a branch to view commits, diffs, and actions.")
                )
            }
        }
        .navigationTitle("\(project.name) — Git")
        .onAppear { refreshBranches() }
    }

    // MARK: - Sidebar

    private var branchListSidebar: some View {
        List(selection: $selectedBranch) {
            if isLoading && branches.isEmpty {
                ProgressView("Loading branches...")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if branches.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Branches",
                        systemImage: "arrow.triangle.branch",
                        description: Text("No maestro task branches found. Agent runs with worktrees will create branches here.")
                    )
                }
            } else {
                let withConflicts = branches.filter { $0.hasConflict }
                let withoutConflicts = branches.filter { !$0.hasConflict }

                if !withConflicts.isEmpty {
                    Section("Conflicts") {
                        ForEach(withConflicts, id: \.name) { branch in
                            BranchRow(branch: branch, project: project)
                                .tag(branch.name)
                        }
                    }
                }

                Section(withConflicts.isEmpty ? "Branches" : "Ready") {
                    ForEach(withoutConflicts, id: \.name) { branch in
                        BranchRow(branch: branch, project: project)
                            .tag(branch.name)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        .toolbar {
            ToolbarItem {
                Button(action: refreshBranches) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
    }

    // MARK: - Actions

    private func refreshBranches() {
        let root = project.workspaceRoot
        guard !root.isEmpty, FileManager.default.fileExists(atPath: root) else { return }

        isLoading = true
        let base = baseBranch

        Task.detached {
            let result = GitService.listMaestroBranches(in: root, baseBranch: base)
            await MainActor.run {
                branches = result.sorted {
                    ($0.lastCommitDate ?? .distantPast) > ($1.lastCommitDate ?? .distantPast)
                }
                isLoading = false
                lastRefresh = Date()
            }
        }
    }
}

// MARK: - Branch Row

private struct BranchRow: View {
    let branch: GitBranchInfo
    let project: Project

    private var taskForBranch: ProjectTask? {
        guard let taskId = branch.taskId else { return nil }
        return project.tasks?.first { $0.id == taskId }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                if let task = taskForBranch {
                    Text(task.title)
                        .font(.body)
                        .lineLimit(1)
                    Text(branch.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(branch.name)
                        .font(.body)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if branch.aheadCount > 0 {
                        Label("\(branch.aheadCount)", systemImage: "arrow.up")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    if branch.behindCount > 0 {
                        Label("\(branch.behindCount)", systemImage: "arrow.down")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if let date = branch.lastCommitDate {
                        Text(date.relativeFormatted)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Push status
            if branch.isPushed {
                Image(systemName: "cloud.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Pushed to remote")
            } else {
                Image(systemName: "cloud")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("Not pushed")
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if branch.hasConflict {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help("Has merge conflicts")
        } else if branch.isPushed {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Pushed to remote")
        } else if branch.aheadCount > 0 {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.blue)
                .help("\(branch.aheadCount) commit(s) ahead")
        } else {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Branch Detail View

struct GitBranchDetailView: View {
    let branch: GitBranchInfo
    let project: Project
    let baseBranch: String
    let onRefresh: () -> Void

    @Environment(\.isDarkerMode) private var isDarkerMode
    @State private var commits: [(sha: String, shortSha: String, message: String, authorName: String, authorDate: Date)] = []
    @State private var diffFiles: [GitDiffFile] = []
    @State private var expandedFile: String?
    @State private var fileDiffContent: String?
    @State private var isLoadingDiff = false
    @State private var actionMessage: String?
    @State private var actionIsError = false
    @State private var isPerformingAction = false
    @State private var showMergeConfirmation = false
    @State private var showRebaseConfirmation = false
    @State private var showPRSheet = false
    @State private var prTitle = ""
    @State private var prBody = ""

    private var root: String { project.workspaceRoot }

    private var taskForBranch: ProjectTask? {
        guard let taskId = branch.taskId else { return nil }
        return project.tasks?.first { $0.id == taskId }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                actionButtons
                if let msg = actionMessage {
                    actionMessageBanner(msg)
                }
                commitsSection
                diffSection
            }
            .padding()
        }
        .onAppear { loadDetails() }
        .onChange(of: branch.name) { loadDetails() }
        .sheet(isPresented: $showPRSheet) { prSheet }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    if let task = taskForBranch {
                        Text(task.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    HStack(spacing: 4) {
                        Text(branch.name)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(baseBranch)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 16) {
                if branch.aheadCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .foregroundStyle(.green)
                        Text("\(branch.aheadCount) ahead")
                            .foregroundStyle(.green)
                    }
                    .font(.subheadline)
                }
                if branch.behindCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .foregroundStyle(.orange)
                        Text("\(branch.behindCount) behind")
                            .foregroundStyle(.orange)
                    }
                    .font(.subheadline)
                }
                if branch.isPushed {
                    HStack(spacing: 4) {
                        Image(systemName: "cloud.fill")
                        Text("Pushed")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                if branch.hasConflict {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Has conflicts")
                            .foregroundStyle(.red)
                    }
                    .font(.subheadline)
                }
                if !diffFiles.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                        Text("\(diffFiles.count) file\(diffFiles.count == 1 ? "" : "s") changed")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 10) {
            // Push
            Button {
                performAction {
                    GitService.push(branch: branch.name, in: root)
                }
            } label: {
                Label("Push", systemImage: "arrow.up.to.line")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPerformingAction || branch.aheadCount == 0 && branch.isPushed)

            // Create PR
            Button {
                prTitle = taskForBranch?.title ?? branch.name
                prBody = ""
                showPRSheet = true
            } label: {
                Label("Create PR", systemImage: "arrow.triangle.pull")
            }
            .buttonStyle(.bordered)
            .disabled(isPerformingAction)

            // Merge
            Button {
                showMergeConfirmation = true
            } label: {
                Label("Merge", systemImage: "arrow.triangle.merge")
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .disabled(isPerformingAction || branch.hasConflict || branch.aheadCount == 0)
            .confirmationDialog("Merge \(branch.name) into \(baseBranch)?", isPresented: $showMergeConfirmation) {
                Button("Merge") {
                    performAction {
                        GitService.merge(branch: branch.name, into: baseBranch, in: root)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }

            // Rebase
            Button {
                showRebaseConfirmation = true
            } label: {
                Label("Rebase", systemImage: "arrow.uturn.up")
            }
            .buttonStyle(.bordered)
            .tint(.purple)
            .disabled(isPerformingAction || branch.behindCount == 0)
            .confirmationDialog("Rebase \(branch.name) onto \(baseBranch)?", isPresented: $showRebaseConfirmation) {
                Button("Rebase") {
                    performAction {
                        GitService.rebase(branch: branch.name, onto: baseBranch, in: root)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }

            if isPerformingAction {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func actionMessageBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: actionIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(actionIsError ? .red : .green)
            Text(message)
                .font(.subheadline)
                .textSelection(.enabled)
            Spacer()
            Button {
                actionMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((actionIsError ? Color.red : Color.green).opacity(0.1))
        )
    }

    // MARK: - Commits

    private var commitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Commits")
                .font(.headline)

            if commits.isEmpty {
                Text("No commits ahead of \(baseBranch).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(commits.reversed().enumerated()), id: \.offset) { _, commit in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
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
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Diff

    private var diffSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Changed Files")
                    .font(.headline)
                if !diffFiles.isEmpty {
                    let totalAdds = diffFiles.reduce(0) { $0 + $1.additions }
                    let totalDels = diffFiles.reduce(0) { $0 + $1.deletions }
                    Text("+\(totalAdds)")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("-\(totalDels)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if diffFiles.isEmpty {
                Text("No file changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diffFiles, id: \.path) { file in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            toggleFileDiff(file)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: expandedFile == file.path ? "chevron.down" : "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 12)

                                fileStatusBadge(file.status)

                                Text(file.path)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                HStack(spacing: 4) {
                                    Text("+\(file.additions)")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                    Text("-\(file.deletions)")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if expandedFile == file.path {
                            if isLoadingDiff {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else if let diffContent = fileDiffContent {
                                DiffContentView(content: diffContent)
                                    .padding(.leading, 28)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.controlBackground(darker: isDarkerMode))
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func fileStatusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "A": return ("A", .green)
            case "D": return ("D", .red)
            case "R": return ("R", .purple)
            default: return ("M", .orange)
            }
        }()

        Text(label)
            .font(.system(.caption2, design: .monospaced))
            .fontWeight(.bold)
            .frame(width: 18, height: 18)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color)
    }

    // MARK: - PR Sheet

    private var prSheet: some View {
        VStack(spacing: 16) {
            Text("Create Pull Request")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("PR Title", text: $prTitle)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $prBody)
                    .font(.body)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            }

            HStack(spacing: 8) {
                Text("\(branch.name)")
                    .font(.system(.caption, design: .monospaced))
                Image(systemName: "arrow.right")
                    .font(.caption)
                Text(baseBranch)
                    .font(.system(.caption, design: .monospaced))
            }
            .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") {
                    showPRSheet = false
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
                Spacer()
                Button("Create PR") {
                    showPRSheet = false
                    performAction {
                        GitService.createPR(
                            branch: branch.name,
                            title: prTitle,
                            body: prBody,
                            baseBranch: baseBranch,
                            in: root
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(prTitle.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    // MARK: - Actions

    private func loadDetails() {
        let root = self.root
        let branchName = branch.name
        let base = baseBranch

        Task.detached {
            let c = GitService.branchCommits(branch: branchName, baseBranch: base, in: root)
            let d = GitService.diffFiles(branch: branchName, baseBranch: base, in: root)
            await MainActor.run {
                commits = c
                diffFiles = d
                expandedFile = nil
                fileDiffContent = nil
            }
        }
    }

    private func toggleFileDiff(_ file: GitDiffFile) {
        if expandedFile == file.path {
            expandedFile = nil
            fileDiffContent = nil
        } else {
            expandedFile = file.path
            isLoadingDiff = true

            let root = self.root
            let branchName = branch.name
            let base = baseBranch
            let filePath = file.path

            Task.detached {
                let diff = GitService.fileDiff(branch: branchName, baseBranch: base, file: filePath, in: root)
                await MainActor.run {
                    fileDiffContent = diff
                    isLoadingDiff = false
                }
            }
        }
    }

    private func performAction(_ action: @escaping () -> (success: Bool, message: String)) {
        isPerformingAction = true
        actionMessage = nil

        Task.detached {
            let result = action()
            await MainActor.run {
                actionIsError = !result.success
                actionMessage = result.message
                isPerformingAction = false
                if result.success {
                    onRefresh()
                    loadDetails()
                }
            }
        }
    }
}

// MARK: - Diff Content View

private struct DiffContentView: View {
    let content: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(content.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(lineColor(for: line))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(lineBackground(for: line))
                }
            }
            .textSelection(.enabled)
        }
        .frame(maxHeight: 400)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func lineColor(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return .green
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return .red
        } else if line.hasPrefix("@@") {
            return .cyan
        }
        return .primary
    }

    private func lineBackground(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return Color.green.opacity(0.06)
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return Color.red.opacity(0.06)
        } else if line.hasPrefix("@@") {
            return Color.cyan.opacity(0.06)
        }
        return .clear
    }
}
