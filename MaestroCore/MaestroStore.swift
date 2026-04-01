import Foundation
import SwiftData

public struct MaestroStore {
    public static var storeURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let maestroDir = appSupport.appendingPathComponent("Maestro")
        try? FileManager.default.createDirectory(
            at: maestroDir,
            withIntermediateDirectories: true
        )
        return maestroDir.appendingPathComponent("Maestro.store")
    }

    public static var schema: Schema {
        Schema([Project.self, ProjectTask.self, AgentRun.self, TaskComment.self, TaskCommit.self])
    }

    public static func makeContainer(dbPath: String? = nil) throws -> ModelContainer {
        let url = dbPath.map { URL(fileURLWithPath: $0) } ?? storeURL
        let config = ModelConfiguration(url: url)
        return try ModelContainer(
            for: schema,
            configurations: config
        )
    }

    /// Assigns ticket numbers to any tasks that don't have one yet (ticketNumber == 0).
    /// Existing tasks are numbered by creation date within each project.
    public static func assignMissingTicketNumbers(in context: ModelContext) {
        let descriptor = FetchDescriptor<Project>()
        guard let projects = try? context.fetch(descriptor) else { return }

        for project in projects {
            let unnumbered = (project.tasks ?? [])
                .filter { $0.ticketNumber == 0 }
                .sorted { $0.createdDate < $1.createdDate }

            guard !unnumbered.isEmpty else { continue }

            for task in unnumbered {
                project.assignTicketNumber(to: task)
            }
        }

        try? context.save()
    }
}
