import Foundation
import SwiftData

@Model
public final class TaskComment {
    public var id: String = UUID().uuidString
    public var body: String = ""
    public var authorTypeRaw: String = CommentAuthor.user.rawValue
    public var createdDate: Date = Date()

    public var task: ProjectTask?
    public var agentRun: AgentRun?

    public var authorType: CommentAuthor {
        get { CommentAuthor(rawValue: authorTypeRaw) ?? .user }
        set { authorTypeRaw = newValue.rawValue }
    }

    public init(body: String, authorType: CommentAuthor, task: ProjectTask? = nil, agentRun: AgentRun? = nil) {
        self.id = UUID().uuidString
        self.body = body
        self.authorTypeRaw = authorType.rawValue
        self.createdDate = Date()
        self.task = task
        self.agentRun = agentRun
    }
}
