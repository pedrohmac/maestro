import Foundation

public enum TaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case todo = "To do"
    case inProgress = "In Progress"
    case review = "Review"
    case done = "Done"

    public var id: String { rawValue }

    public var color: String {
        switch self {
        case .todo: return "systemBlue"
        case .inProgress: return "systemOrange"
        case .review: return "systemPurple"
        case .done: return "systemGreen"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .todo: return 0
        case .inProgress: return 1
        case .review: return 2
        case .done: return 3
        }
    }

    public var cliName: String {
        switch self {
        case .todo: return "todo"
        case .inProgress: return "in-progress"
        case .review: return "review"
        case .done: return "done"
        }
    }

    public static func fromCLI(_ value: String) -> TaskStatus? {
        switch value.lowercased() {
        case "todo", "to-do", "to do": return .todo
        case "in-progress", "inprogress", "in progress": return .inProgress
        case "review": return .review
        case "done": return .done
        default: return nil
        }
    }
}

public enum Priority: String, Codable, CaseIterable, Identifiable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"

    public var id: String { rawValue }

    public var color: String {
        switch self {
        case .low: return "systemGray"
        case .medium: return "systemBlue"
        case .high: return "systemOrange"
        case .critical: return "systemRed"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .critical: return 3
        }
    }

    public var cliName: String { rawValue.lowercased() }

    public static func fromCLI(_ value: String) -> Priority? {
        switch value.lowercased() {
        case "low": return .low
        case "medium", "med": return .medium
        case "high": return .high
        case "critical", "crit": return .critical
        default: return nil
        }
    }
}

public enum RunStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case queued = "Queued"
    case running = "Running"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
    case timedOut = "Timed Out"
    case rolledBack = "Rolled Back"

    public var id: String { rawValue }

    public var cliName: String {
        switch self {
        case .queued: return "queued"
        case .running: return "running"
        case .completed: return "completed"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        case .timedOut: return "timed-out"
        case .rolledBack: return "rolled-back"
        }
    }

    public static func fromCLI(_ value: String) -> RunStatus? {
        switch value.lowercased() {
        case "queued": return .queued
        case "running": return .running
        case "completed": return .completed
        case "failed": return .failed
        case "cancelled": return .cancelled
        case "timed-out", "timedout", "timed out": return .timedOut
        case "rolled-back", "rolledback", "rolled back": return .rolledBack
        default: return nil
        }
    }
}

public enum WorkspaceStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case shared = "Shared"
    case isolated = "Isolated"

    public var id: String { rawValue }

    public var cliName: String { rawValue.lowercased() }

    public static func fromCLI(_ value: String) -> WorkspaceStrategy? {
        switch value.lowercased() {
        case "shared": return .shared
        case "isolated": return .isolated
        default: return nil
        }
    }
}

public enum DispatchMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual = "Manual"
    case auto = "Auto"

    public var id: String { rawValue }

    public var cliName: String { rawValue.lowercased() }

    public static func fromCLI(_ value: String) -> DispatchMode? {
        switch value.lowercased() {
        case "manual": return .manual
        case "auto": return .auto
        default: return nil
        }
    }
}

public enum CommentAuthor: String, Codable, CaseIterable, Identifiable, Sendable {
    case user = "User"
    case agent = "Agent"
    case narration = "Narration"
    public var id: String { rawValue }
}

public enum RuleAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case allow = "Allow"
    case deny = "Deny"
    public var id: String { rawValue }
}

public struct KanbanColumn: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var color: String   // e.g. "systemBlue", "systemTeal"
    public var order: Int
    public var mappedStatus: String?  // TaskStatus.rawValue — drives business logic (auto-dispatch, completedDate)

    public init(id: String = UUID().uuidString, name: String, color: String = "systemBlue", order: Int = 0, mappedStatus: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.order = order
        self.mappedStatus = mappedStatus
    }

    public var taskStatus: TaskStatus? {
        guard let mappedStatus else { return nil }
        return TaskStatus(rawValue: mappedStatus)
    }

    public static var defaultColumns: [KanbanColumn] {
        [
            KanbanColumn(id: "default-todo", name: "To do", color: "systemBlue", order: 0, mappedStatus: TaskStatus.todo.rawValue),
            KanbanColumn(id: "default-in-progress", name: "In Progress", color: "systemOrange", order: 1, mappedStatus: TaskStatus.inProgress.rawValue),
            KanbanColumn(id: "default-review", name: "Review", color: "systemPurple", order: 2, mappedStatus: TaskStatus.review.rawValue),
            KanbanColumn(id: "default-done", name: "Done", color: "systemGreen", order: 3, mappedStatus: TaskStatus.done.rawValue),
        ]
    }
}

public struct PermissionRule: Codable, Identifiable, Sendable, Hashable {
    public var id: String = UUID().uuidString
    public var toolName: String       // "Bash", "Write", "*" (wildcard)
    public var action: RuleAction
    public var pathPattern: String?   // optional glob e.g. "/etc/*"

    public init(toolName: String, action: RuleAction, pathPattern: String? = nil) {
        self.id = UUID().uuidString
        self.toolName = toolName
        self.action = action
        self.pathPattern = pathPattern
    }
}
