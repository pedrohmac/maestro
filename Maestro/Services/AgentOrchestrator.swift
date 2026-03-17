import Foundation
import SwiftData
import MaestroCore

@MainActor
@Observable
final class AgentOrchestrator {
    var activeRunners: [String: AgentRunner] = [:]  // taskId -> runner
    var claudePath: String = "/usr/local/bin/claude"
    var defaultMaxConcurrency: Int = 3

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

        let prompt = PromptBuilder.build(task: task, project: project, workspacePath: project.workspaceRoot)
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

    func sendMessage(to taskId: String, message: String) {
        activeRunners[taskId]?.sendMessage(message)
    }

    func respondToPermission(taskId: String, requestId: String, granted: Bool) {
        activeRunners[taskId]?.resolvePendingPermission(requestId: requestId, granted: granted, auto: false)
    }

    func getRunner(for taskId: String) -> AgentRunner? {
        activeRunners[taskId]
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
        for commit in commits {
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
