import Foundation
import SwiftData

@Model
public final class AgentRun {
    public var id: String = UUID().uuidString
    public var task: ProjectTask?
    public var sessionId: String? = nil
    public var startedAt: Date = Date()
    public var completedAt: Date? = nil
    public var exitCode: Int? = nil
    public var log: String = ""
    public var statusRaw: String = RunStatus.queued.rawValue
    public var tokensUsed: Int? = nil
    public var costUSD: Double? = nil
    public var eventsData: Data? = nil
    public var projectId: String = ""
    public var taskTitle: String = ""
    public var ticketNumber: Int = 0

    // Rollback tracking
    public var preRunHeadSha: String? = nil
    public var postRunHeadSha: String? = nil
    public var isRolledBack: Bool = false
    public var rollbackDate: Date? = nil
    public var workspacePath: String? = nil

    public var status: RunStatus {
        get { RunStatus(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }

    public var duration: TimeInterval? {
        guard let completed = completedAt else {
            return Date().timeIntervalSince(startedAt)
        }
        return completed.timeIntervalSince(startedAt)
    }

    public var durationFormatted: String {
        guard let dur = duration else { return "\u{2014}" }
        let minutes = Int(dur) / 60
        let seconds = Int(dur) % 60
        return "\(minutes)m \(seconds)s"
    }

    public var relativeTimeFormatted: String {
        startedAt.relativeFormatted
    }

    public var canRollback: Bool {
        !isRolledBack
            && preRunHeadSha != nil
            && postRunHeadSha != nil
            && preRunHeadSha != postRunHeadSha
            && (status == .completed || status == .failed)
    }

    public init(task: ProjectTask?) {
        self.id = UUID().uuidString
        self.task = task
        self.taskTitle = task?.title ?? "Unknown Task"
        self.ticketNumber = task?.ticketNumber ?? 0
        self.projectId = task?.project?.id ?? ""
        self.startedAt = Date()
    }
}
