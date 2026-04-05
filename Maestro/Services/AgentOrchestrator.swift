import Foundation
import SwiftData
import MaestroCore

@MainActor
@Observable
final class ClaudeMDGeneration {
    var isGenerating: Bool = true
    var result: String?
    var error: String?
    fileprivate var process: Process?
    fileprivate var task: Task<Void, Never>?
}

@MainActor
@Observable
final class AgentOrchestrator {
    var activeRunners: [String: AgentRunner] = [:]  // taskId -> runner
    var chatRunners: [String: AgentRunner] = [:]   // projectId -> chat runner
    var claudeMDGenerations: [String: ClaudeMDGeneration] = [:]  // projectId -> generation
    var claudePath: String = "/usr/local/bin/claude"
    var defaultMaxConcurrency: Int = 3
    var appState: AppState?

    var modelContext: ModelContext?
    let pool: AgentPool

    // Narration state: throttle and track the latest narration comment per task
    private var lastNarrationDate: [String: Date] = [:]
    private var lastNarrationComment: [String: TaskComment] = [:]
    private static let narrationThrottleSeconds: TimeInterval = 4

    init() {
        self.pool = AgentPool(maxConcurrency: 3)
        loadSettings()
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public API

    func runAgent(task: ProjectTask, project: Project) {
        guard appState?.canRunAgents == true else {
            print("[Agent] Blocked: license check failed or AppState not configured")
            return
        }
        let taskId = task.id
        let taskTitle = task.title
        print("[Agent] runAgent called for task: \(taskTitle) (id: \(taskId))")

        guard activeRunners[taskId] == nil else {
            print("[Agent] Runner already active for \(taskId), skipping")
            return
        }

        let runner = AgentRunner(taskId: taskId, taskTitle: taskTitle)
        activeRunners[taskId] = runner

        // Create agent run record
        let agentRun = AgentRun(task: task)
        agentRun.status = .running
        modelContext?.insert(agentRun)
        print("[Agent] AgentRun inserted into modelContext, context is \(modelContext == nil ? "nil" : "set")")

        // Gather previous discussion context if this task has been run before
        let previousDiscussion: [TaskComment]? = {
            guard let comments = task.comments else { return nil }
            let discussion = comments
                .filter { $0.authorType == .agent || $0.authorType == .user }
                .sorted { $0.createdDate < $1.createdDate }
            return discussion.isEmpty ? nil : discussion
        }()

        let prompt = PromptBuilder.build(task: task, project: project, workspacePath: project.workspaceRoot, previousDiscussion: previousDiscussion)
        let allowedTools = project.defaultAllowedTools
        let maxTurns = project.maxTurns
        let maxBudget = project.maxBudgetUSD
        let workflowPrompt = project.workflowPrompt.isEmpty ? nil : project.workflowPrompt
        let claudeP = claudePath

        let isolatedWorkspace = project.workspaceStrategy == .isolated
        let taskUsesWorktree = task.useWorktree
        let permissionRules = project.permissionRules

        Task {
            // Sync pool concurrency with project setting
            await pool.updateMaxConcurrency(project.maxConcurrentAgents)

            // Resolve workspace
            let workspacePath: String
            do {
                if taskUsesWorktree {
                    workspacePath = try WorkspaceManager.createTaskWorktree(task: task, project: project)
                    await MainActor.run { task.worktreePath = workspacePath }
                } else {
                    workspacePath = try WorkspaceManager.resolveWorkspace(task: task, project: project)
                }
                print("[Agent] Workspace resolved: \(workspacePath)")
            } catch {
                print("[Agent] Workspace error: \(error.localizedDescription)")
                runner.cancel()
                agentRun.status = .failed
                agentRun.log = "Workspace error: \(error.localizedDescription)"
                agentRun.completedAt = Date()
                self.activeRunners.removeValue(forKey: taskId)
                try? self.modelContext?.save()
                return
            }

            // Capture pre-run Git HEAD SHA for rollback
            agentRun.preRunHeadSha = WorkspaceManager.gitHeadSha(in: workspacePath)
            agentRun.workspacePath = workspacePath

            await pool.registerRunner(runner, for: taskId)

            // Start collecting events
            let eventStream = runner.eventStream()

            Task {
                for await event in eventStream {
                    await MainActor.run {
                        self.handleEvent(event, run: agentRun, taskId: taskId, task: task, permissionRules: permissionRules)
                    }
                }

                await MainActor.run {
                    agentRun.completedAt = Date()
                    if agentRun.status == .running {
                        agentRun.status = runner.wasCancelled ? .cancelled : .completed
                    }

                    // Auto-commit only on successful completion
                    if agentRun.status == .completed {
                        WorkspaceManager.gitAutoCommit(
                            message: "[maestro] Agent changes for: \(taskTitle)",
                            in: workspacePath
                        )
                    }

                    agentRun.postRunHeadSha = WorkspaceManager.gitHeadSha(in: workspacePath)

                    if !runner.output.isEmpty {
                        agentRun.log = runner.output
                    }
                    if !runner.events.isEmpty {
                        agentRun.eventsData = try? JSONEncoder().encode(runner.events)
                    }
                    self.postAgentComment(runner: runner, task: task, agentRun: agentRun)
                    self.collectCommits(for: agentRun, task: task)
                    self.clearNarrationState(for: taskId)

                    // Move task to Review column on successful completion
                    if agentRun.status == .completed {
                        task.status = .review
                        if let column = task.project?.columnForStatus(.review) {
                            task.columnId = column.id
                            // Place task at the top of the review column
                            let columnTasks = (task.project?.tasks ?? []).filter { $0.columnId == column.id && $0.id != task.id }
                            for existing in columnTasks {
                                existing.order += 1
                            }
                            task.order = 0
                        }
                    }

                    self.activeRunners.removeValue(forKey: taskId)

                    // Clean up isolated workspace after run completes
                    if isolatedWorkspace {
                        WorkspaceManager.cleanup(task: task, project: project)
                    }

                    try? self.modelContext?.save()
                }

                await pool.unregisterRunner(for: taskId)
            }

            // Start the agent
            await runner.start(
                prompt: prompt,
                workspacePath: workspacePath,
                allowedTools: allowedTools,
                maxTurns: maxTurns,
                maxBudget: maxBudget,
                systemPrompt: workflowPrompt,
                claudePath: claudeP
            )
        }
    }

    func resumeAgent(task: ProjectTask, project: Project, sessionId: String) {
        guard appState?.canRunAgents == true else {
            print("[Agent] Blocked: license check failed or AppState not configured")
            return
        }
        let taskId = task.id
        let taskTitle = task.title

        guard activeRunners[taskId] == nil else { return }

        let runner = AgentRunner(taskId: taskId, taskTitle: taskTitle)
        activeRunners[taskId] = runner

        let agentRun = AgentRun(task: task)
        agentRun.status = .running
        agentRun.sessionId = sessionId
        modelContext?.insert(agentRun)

        let claudeP = claudePath
        let resumePrompt = PromptBuilder.buildResume(task: task)
        let isolatedWorkspace = project.workspaceStrategy == .isolated
        let taskUsesWorktree = task.useWorktree
        let permissionRules = project.permissionRules

        Task {
            await pool.updateMaxConcurrency(project.maxConcurrentAgents)

            let workspacePath: String
            do {
                if taskUsesWorktree {
                    workspacePath = try WorkspaceManager.createTaskWorktree(task: task, project: project)
                    await MainActor.run { task.worktreePath = workspacePath }
                } else {
                    workspacePath = try WorkspaceManager.resolveWorkspace(task: task, project: project)
                }
            } catch {
                runner.cancel()
                agentRun.status = .failed
                agentRun.log = "Workspace error: \(error.localizedDescription)"
                agentRun.completedAt = Date()
                self.activeRunners.removeValue(forKey: taskId)
                try? self.modelContext?.save()
                return
            }

            // Capture pre-run Git HEAD SHA for rollback and commit tracking
            agentRun.preRunHeadSha = WorkspaceManager.gitHeadSha(in: workspacePath)
            agentRun.workspacePath = workspacePath

            await pool.registerRunner(runner, for: taskId)

            let eventStream = runner.eventStream()

            Task {
                for await event in eventStream {
                    await MainActor.run {
                        self.handleEvent(event, run: agentRun, taskId: taskId, task: task, permissionRules: permissionRules)
                    }
                }

                await MainActor.run {
                    agentRun.completedAt = Date()
                    if agentRun.status == .running {
                        agentRun.status = runner.wasCancelled ? .cancelled : .completed
                    }

                    // Auto-commit only on successful completion
                    if agentRun.status == .completed {
                        WorkspaceManager.gitAutoCommit(
                            message: "[maestro] Agent changes for: \(taskTitle)",
                            in: workspacePath
                        )
                    }

                    agentRun.postRunHeadSha = WorkspaceManager.gitHeadSha(in: workspacePath)

                    if !runner.output.isEmpty {
                        agentRun.log = runner.output
                    }
                    if !runner.events.isEmpty {
                        agentRun.eventsData = try? JSONEncoder().encode(runner.events)
                    }
                    self.postAgentComment(runner: runner, task: task, agentRun: agentRun)
                    self.collectCommits(for: agentRun, task: task)
                    self.clearNarrationState(for: taskId)

                    // Move task to Review column on successful completion
                    if agentRun.status == .completed {
                        task.status = .review
                        if let column = task.project?.columnForStatus(.review) {
                            task.columnId = column.id
                            // Place task at the top of the review column
                            let columnTasks = (task.project?.tasks ?? []).filter { $0.columnId == column.id && $0.id != task.id }
                            for existing in columnTasks {
                                existing.order += 1
                            }
                            task.order = 0
                        }
                    }

                    self.activeRunners.removeValue(forKey: taskId)

                    if isolatedWorkspace {
                        WorkspaceManager.cleanup(task: task, project: project)
                    }

                    try? self.modelContext?.save()
                }

                await pool.unregisterRunner(for: taskId)
            }

            await runner.resume(
                sessionId: sessionId,
                prompt: resumePrompt,
                workspacePath: workspacePath,
                claudePath: claudeP
            )
        }
    }

    func cancelAgent(taskId: String) {
        if let runner = activeRunners[taskId] {
            runner.cancel()
            // Don't remove here — let the event stream completion handler
            // remove it after saving the log
        }
        Task {
            await pool.cancel(taskId: taskId)
        }
    }

    func cancelAll() {
        for runner in activeRunners.values {
            runner.cancel()
        }
        activeRunners.removeAll()
        Task {
            await pool.cancelAll()
        }
    }

    func rollbackRun(_ run: AgentRun) -> String? {
        guard run.canRollback,
              let sha = run.preRunHeadSha,
              let workspace = run.workspacePath else {
            return "Cannot rollback: missing SHA or workspace path."
        }
        let error = WorkspaceManager.gitResetHard(to: sha, in: workspace)
        if let error { return error }
        run.isRolledBack = true
        run.rollbackDate = Date()
        run.status = .rolledBack
        try? modelContext?.save()
        return nil
    }

    func rollbackCommit(_ commit: TaskCommit, task: ProjectTask) -> String? {
        let workspace: String
        if let worktreePath = task.worktreePath, !worktreePath.isEmpty {
            workspace = worktreePath
        } else if let projectRoot = task.project?.workspaceRoot, !projectRoot.isEmpty {
            workspace = projectRoot
        } else {
            return "Cannot rollback: no workspace path found."
        }
        let error = WorkspaceManager.gitResetHard(to: "\(commit.sha)~1", in: workspace)
        if let error { return error }
        try? modelContext?.save()
        return nil
    }

    func sendMessage(to taskId: String, message: String) {
        activeRunners[taskId]?.sendMessage(message)
    }

    func respondToPermission(taskId: String, requestId: String, granted: Bool) {
        activeRunners[taskId]?.resolvePendingPermission(requestId: requestId, granted: granted, auto: false)
    }

    func getRunner(for taskId: String) -> AgentRunner? {
        activeRunners[taskId]
    }

    // MARK: - Chat

    func startChat(project: Project, initialMessage: String) {
        let projectId = project.id
        guard chatRunners[projectId] == nil else { return }

        let runner = AgentRunner(taskId: "chat-\(projectId)", taskTitle: "Chat")
        chatRunners[projectId] = runner

        // Record the user's initial message
        runner.addUserMessage(initialMessage)

        let workspacePath = project.workspaceRoot
        let claudeP = claudePath
        let permissionRules = project.permissionRules

        Task {
            let eventStream = runner.eventStream()

            Task {
                for await event in eventStream {
                    await MainActor.run {
                        self.handleChatEvent(event, runner: runner, projectId: projectId, permissionRules: permissionRules)
                    }
                }
                // Don't remove the runner here — keep it so the UI can still
                // display the conversation after the process exits. The runner
                // is cleaned up explicitly via endChat() or when a new chat starts.
            }

            let prompt = """
            You are a helpful assistant for this project. The user will ask you questions about the codebase, \
            testing, implementation details, and other development topics. Be conversational, concise, and helpful. \
            Read code when needed to give accurate answers. Do not make changes to the codebase unless explicitly asked.

            User's question: \(initialMessage)
            """

            await runner.start(
                prompt: prompt,
                workspacePath: workspacePath,
                allowedTools: "Read,Grep,Glob,Bash(read-only),WebSearch,WebFetch",
                maxTurns: 0,
                maxBudget: nil,
                systemPrompt: nil,
                claudePath: claudeP,
                timeoutMinutes: 60
            )
        }
    }

    func sendChatMessage(projectId: String, message: String) {
        chatRunners[projectId]?.sendMessage(message)
    }

    func resumeChat(project: Project, message: String) {
        let projectId = project.id
        guard let runner = chatRunners[projectId],
              let sessionId = runner.sessionId else { return }

        // Record the user's follow-up message
        runner.addUserMessage(message)

        let workspacePath = project.workspaceRoot
        let claudeP = claudePath
        let permissionRules = project.permissionRules

        Task {
            let eventStream = runner.eventStream()

            Task {
                for await event in eventStream {
                    await MainActor.run {
                        self.handleChatEvent(event, runner: runner, projectId: projectId, permissionRules: permissionRules)
                    }
                }
            }

            await runner.resume(
                sessionId: sessionId,
                prompt: message,
                workspacePath: workspacePath,
                claudePath: claudeP,
                timeoutMinutes: 60
            )
        }
    }

    func endChat(projectId: String) {
        if let runner = chatRunners[projectId] {
            runner.cancel()
        }
        chatRunners.removeValue(forKey: projectId)
    }

    func getChatRunner(for projectId: String) -> AgentRunner? {
        chatRunners[projectId]
    }

    // MARK: - CLAUDE.md Generation

    func generateClaudeMD(projectId: String, workspacePath: String) {
        if let existing = claudeMDGenerations[projectId], existing.isGenerating {
            return
        }

        let generation = ClaudeMDGeneration()
        claudeMDGenerations[projectId] = generation

        let claudeP = claudePath

        generation.task = Task {
            let resolvedPath = await ClaudePathResolver.resolve(preferredPath: claudeP)

            let prompt = """
            Analyze this codebase and generate a CLAUDE.md file that will give AI coding agents instant context about this project. Output ONLY the raw markdown content with no preamble or explanation.

            Cover these sections:
            - Project name and one-paragraph description of what it does
            - Tech stack (languages, frameworks, key dependencies)
            - Project structure (key directories and what lives where)
            - Build commands (how to build, test, run)
            - Key architecture decisions
            - Conventions (naming, patterns, anything non-obvious)

            Be concise and specific. Focus on information that would help an agent start working immediately without exploring the codebase first.
            """

            let proc = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            let shellCmd = [resolvedPath, "-p", prompt, "--output-format", "text", "--max-turns", "5", "--allowedTools", "Bash,Read,Glob,Grep"]
                .map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
                .joined(separator: " ")

            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-l", "-c", shellCmd]
            proc.currentDirectoryURL = URL(fileURLWithPath: workspacePath)
            proc.standardOutput = stdoutPipe
            proc.standardError = stderrPipe
            proc.environment = [
                "HOME": NSHomeDirectory(),
                "USER": NSUserName(),
                "SHELL": "/bin/zsh",
                "TERM": "xterm-256color",
                "LANG": "en_US.UTF-8",
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "TMPDIR": NSTemporaryDirectory(),
                "NO_COLOR": "1"
            ]

            generation.process = proc

            do {
                try proc.run()
            } catch {
                generation.error = "Failed to start Claude: \(error.localizedDescription)"
                generation.isGenerating = false
                generation.process = nil
                return
            }

            let (output, errorOutput, exitStatus) = await withCheckedContinuation { (continuation: CheckedContinuation<(String, String, Int32), Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    var stderrData = Data()
                    let stderrQueue = DispatchQueue(label: "claudemd.stderr")
                    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if data.isEmpty {
                            stderrPipe.fileHandleForReading.readabilityHandler = nil
                        } else {
                            stderrQueue.sync { stderrData.append(data) }
                        }
                    }

                    let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()

                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    let errorOutput = stderrQueue.sync {
                        String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    }

                    var output = String(data: stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if let headingRange = output.range(of: "(?m)^#", options: .regularExpression) {
                        output = String(output[headingRange.lowerBound...])
                    }

                    continuation.resume(returning: (output, errorOutput, proc.terminationStatus))
                }
            }

            generation.process = nil

            if Task.isCancelled {
                generation.isGenerating = false
                return
            }

            if exitStatus != 0 {
                let errorSuffix = errorOutput.isEmpty ? "" : ": \(String(errorOutput.suffix(200)))"
                generation.error = "Claude exited with code \(exitStatus)\(errorSuffix)"
            } else if output.isEmpty {
                generation.error = "Claude produced no output"
            } else {
                generation.result = output
                generation.error = nil
            }

            generation.isGenerating = false
        }
    }

    func cancelClaudeMDGeneration(projectId: String) {
        guard let generation = claudeMDGenerations[projectId] else { return }
        generation.task?.cancel()
        generation.process?.terminate()
        claudeMDGenerations.removeValue(forKey: projectId)
    }

    func clearClaudeMDGeneration(projectId: String) {
        claudeMDGenerations.removeValue(forKey: projectId)
    }

    private func handleChatEvent(_ event: AgentEvent, runner: AgentRunner, projectId: String, permissionRules: [PermissionRule]) {
        switch event {
        case .result(let sessionId, _, _, _):
            if let sid = sessionId {
                runner.sessionId = sid
            }
        case .permissionRequest(let toolName, let input, let requestId):
            runner.addPendingPermission(requestId: requestId, toolName: toolName, input: input)
            if let action = PermissionRuleEngine.evaluate(toolName: toolName, input: input, rules: permissionRules) {
                runner.resolvePendingPermission(requestId: requestId, granted: action == .allow, auto: true)
            }
        default:
            break
        }
    }

    func deleteRun(_ run: AgentRun) {
        // Cancel if still running
        if run.status == .running, let taskId = run.task?.id {
            cancelAgent(taskId: taskId)
        }
        modelContext?.delete(run)
        try? modelContext?.save()
    }

    func deleteRuns(_ runs: [AgentRun]) {
        for run in runs {
            if run.status == .running, let taskId = run.task?.id {
                cancelAgent(taskId: taskId)
            }
            modelContext?.delete(run)
        }
        try? modelContext?.save()
    }

    // MARK: - Private

    private func handleEvent(_ event: AgentEvent, run: AgentRun, taskId: String, task: ProjectTask, permissionRules: [PermissionRule]) {
        print("[Agent] handleEvent for \(taskId): \(event)")
        switch event {
        case .result(let sessionId, let costUSD, let tokensUsed, _):
            if let sid = sessionId { run.sessionId = sid }
            if let cost = costUSD { run.costUSD = cost }
            if let tokens = tokensUsed { run.tokensUsed = tokens }
        case .error(let message):
            run.status = .failed
            run.log += "\n[ERROR] \(message)"
        case .toolError(let message):
            run.log += "\n[TOOL ERROR] \(message)"
        case .permissionRequest(let toolName, let input, let requestId):
            if let runner = activeRunners[taskId] {
                runner.addPendingPermission(requestId: requestId, toolName: toolName, input: input)
                if let action = PermissionRuleEngine.evaluate(toolName: toolName, input: input, rules: permissionRules) {
                    runner.resolvePendingPermission(requestId: requestId, granted: action == .allow, auto: true)
                }
                // else: stays pending, user must approve via task sidebar
            }
        default:
            break
        }

        // Narration: translate events to plain English progress updates
        if let narration = NarrationEngine.narrate(event: event) {
            postNarration(narration, taskId: taskId, task: task, agentRun: run)
        }
    }

    // MARK: - Narration

    private func postNarration(_ text: String, taskId: String, task: ProjectTask, agentRun: AgentRun) {
        guard let ctx = modelContext else { return }

        let now = Date()
        let throttle = Self.narrationThrottleSeconds

        // Throttle: skip if we narrated too recently (unless this is the first one)
        if let lastDate = lastNarrationDate[taskId],
           now.timeIntervalSince(lastDate) < throttle,
           lastNarrationComment[taskId] != nil {
            // Update the body of the existing comment with the latest line instead
            // so we always show the most recent action even when throttled
            if let existing = lastNarrationComment[taskId] {
                let lines = existing.body.components(separatedBy: "\n")
                if let lastLine = lines.last, lastLine != text {
                    // Replace the last line with the new text
                    var updatedLines = lines
                    updatedLines[updatedLines.count - 1] = text
                    existing.body = updatedLines.joined(separator: "\n")
                }
            }
            return
        }

        lastNarrationDate[taskId] = now

        if let existing = lastNarrationComment[taskId] {
            // Append new narration line to the existing comment
            existing.body += "\n" + text
        } else {
            // Create the first narration comment for this run
            let comment = TaskComment(body: text, authorType: .narration, task: task, agentRun: agentRun)
            ctx.insert(comment)
            lastNarrationComment[taskId] = comment
        }
    }

    private func clearNarrationState(for taskId: String) {
        lastNarrationDate.removeValue(forKey: taskId)
        lastNarrationComment.removeValue(forKey: taskId)
    }

    // MARK: - Agent Comments

    private func extractAgentSummary(from runner: AgentRunner) -> String? {
        for event in runner.events.reversed() {
            if case .assistantText(let text) = event {
                return text
            }
        }
        return nil
    }

    private func postAgentComment(runner: AgentRunner, task: ProjectTask, agentRun: AgentRun) {
        guard let ctx = modelContext else { return }
        let summary = extractAgentSummary(from: runner) ?? "Agent run completed."
        let comment = TaskComment(body: summary, authorType: .agent, task: task, agentRun: agentRun)
        ctx.insert(comment)
    }

    // MARK: - Commit Collection

    private func collectCommits(for run: AgentRun, task: ProjectTask) {
        guard let ctx = modelContext,
              let preSha = run.preRunHeadSha,
              let postSha = run.postRunHeadSha,
              let workspace = run.workspacePath,
              preSha != postSha else { return }

        let commits = WorkspaceManager.gitLogBetween(from: preSha, to: postSha, in: workspace)
        guard !commits.isEmpty else { return }

        // Build set of commit SHAs already assigned to other tasks.
        // This prevents duplicate attribution when concurrent agents
        // share a workspace and their commit ranges overlap.
        let claimedShas: Set<String>
        do {
            let descriptor = FetchDescriptor<TaskCommit>()
            let existing = try ctx.fetch(descriptor)
            claimedShas = Set(existing.map { $0.sha })
        } catch {
            claimedShas = []
        }

        for commit in commits {
            guard !claimedShas.contains(commit.sha) else { continue }
            let taskCommit = TaskCommit(
                sha: commit.sha,
                message: commit.message,
                authorName: commit.authorName,
                authorDate: commit.authorDate,
                task: task,
                agentRunId: run.id
            )
            ctx.insert(taskCommit)
        }
    }

    // MARK: - Settings persistence

    private func loadSettings() {
        if let path = UserDefaults.standard.string(forKey: "claudePath"), !path.isEmpty {
            claudePath = path
        }
        let concurrency = UserDefaults.standard.integer(forKey: "defaultMaxConcurrency")
        if concurrency > 0 {
            defaultMaxConcurrency = concurrency
        }
    }

    func saveSettings() {
        UserDefaults.standard.set(claudePath, forKey: "claudePath")
        UserDefaults.standard.set(defaultMaxConcurrency, forKey: "defaultMaxConcurrency")
    }
}
