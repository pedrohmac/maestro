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
}
