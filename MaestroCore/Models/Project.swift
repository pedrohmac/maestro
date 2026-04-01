import Foundation
import SwiftData

@Model
public final class Project {
    public var id: String = UUID().uuidString
    public var name: String = ""
    public var projectDescription: String = ""
    public var workspaceRoot: String = ""
    public var defaultBranch: String = ""
    public var workspaceStrategyRaw: String = WorkspaceStrategy.shared.rawValue
    public var dispatchModeRaw: String = DispatchMode.manual.rawValue
    public var workflowPrompt: String = ""
    public var maxConcurrentAgents: Int = 3
    public var defaultAllowedTools: String = "Bash,Read,Edit,Write,Glob,Grep"
    public var maxTurns: Int = 10
    public var maxBudgetUSD: Double? = nil
    public var autoGitEnabled: Bool = false
    public var permissionRulesData: Data? = nil
    public var customColumnsData: Data? = nil
    public var defaultUseWorktree: Bool = false
    public var nextTicketNumber: Int = 1
    public var createdDate: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ProjectTask.project)
    public var tasks: [ProjectTask]? = []

    public var workspaceStrategy: WorkspaceStrategy {
        get { WorkspaceStrategy(rawValue: workspaceStrategyRaw) ?? .shared }
        set { workspaceStrategyRaw = newValue.rawValue }
    }

    public var dispatchMode: DispatchMode {
        get { DispatchMode(rawValue: dispatchModeRaw) ?? .manual }
        set { dispatchModeRaw = newValue.rawValue }
    }

    public var permissionRules: [PermissionRule] {
        get {
            guard let data = permissionRulesData else { return [] }
            return (try? JSONDecoder().decode([PermissionRule].self, from: data)) ?? []
        }
        set { permissionRulesData = try? JSONEncoder().encode(newValue) }
    }

    public var customColumns: [KanbanColumn] {
        get {
            guard let data = customColumnsData else { return KanbanColumn.defaultColumns }
            let columns = (try? JSONDecoder().decode([KanbanColumn].self, from: data)) ?? KanbanColumn.defaultColumns
            return columns.isEmpty ? KanbanColumn.defaultColumns : columns
        }
        set { customColumnsData = try? JSONEncoder().encode(newValue) }
    }

    public func columnForStatus(_ status: TaskStatus) -> KanbanColumn? {
        customColumns.first { $0.mappedStatus == status.rawValue }
    }

    /// Assigns the next sequential ticket number to the given task within this project.
    public func assignTicketNumber(to task: ProjectTask) {
        task.ticketNumber = nextTicketNumber
        nextTicketNumber += 1
    }

    public init(name: String, workspaceRoot: String = "") {
        self.id = UUID().uuidString
        self.name = name
        self.workspaceRoot = workspaceRoot
        self.createdDate = Date()
    }
}
