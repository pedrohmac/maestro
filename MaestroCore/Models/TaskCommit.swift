import Foundation
import SwiftData

@Model
public final class TaskCommit {
    public var id: String = UUID().uuidString
    public var sha: String = ""
    public var shortSha: String = ""
    public var message: String = ""
    public var authorName: String = ""
    public var authorDate: Date = Date()
    public var agentRunId: String? = nil

    public var task: ProjectTask?

    public init(sha: String, message: String, authorName: String, authorDate: Date, task: ProjectTask? = nil, agentRunId: String? = nil) {
        self.id = UUID().uuidString
        self.sha = sha
        self.shortSha = String(sha.prefix(7))
        self.message = message
        self.authorName = authorName
        self.authorDate = authorDate
        self.task = task
        self.agentRunId = agentRunId
    }
}
