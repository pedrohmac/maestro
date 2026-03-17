import Foundation
import SwiftData

@Model
public final class ProjectTask {
    public var id: String = UUID().uuidString
    public var title: String = ""
    public var taskDescription: String = ""
    public var statusRaw: String = TaskStatus.todo.rawValue
    public var priorityRaw: String = Priority.medium.rawValue
    public var order: Int = 0
    public var createdDate: Date = Date()
    public var startDate: Date? = nil
    public var dueDate: Date? = nil
    public var completedDate: Date? = nil
    public var columnId: String = ""
    public var isArchived: Bool = false
    public var archivedDate: Date? = nil
    public var autoGitOverride: Bool? = nil
    public var useWorktree: Bool = false
    public var worktreePath: String? = nil
    public var hasMergeConflict: Bool = false

    public var project: Project?

    @Relationship(deleteRule: .nullify, inverse: \AgentRun.task)
    public var agentRuns: [AgentRun]? = []

    @Relationship(deleteRule: .cascade, inverse: \TaskComment.task)
    public var comments: [TaskComment]? = []

    @Relationship(deleteRule: .cascade, inverse: \TaskCommit.task)
    public var commits: [TaskCommit]? = []

    public var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set {
            statusRaw = newValue.rawValue
            if newValue == .done && completedDate == nil {
                completedDate = Date()
            }
            if newValue == .inProgress && startDate == nil {
                startDate = Date()
            }
        }
    }

    public var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    public var latestRun: AgentRun? {
        agentRuns?.sorted { ($0.startedAt) > ($1.startedAt) }.first
    }

    public var isAgentRunning: Bool {
        latestRun?.statusRaw == RunStatus.running.rawValue
    }

    public var isAutoGitEnabled: Bool {
        if let override = autoGitOverride {
            return override
        }
        return project?.autoGitEnabled ?? false
    }

    public init(title: String, description: String = "", project: Project? = nil) {
        self.id = UUID().uuidString
        self.title = title
        self.taskDescription = description
        self.project = project
        self.createdDate = Date()
    }
}
