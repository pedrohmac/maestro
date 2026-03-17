import ArgumentParser
import Foundation
import MaestroCore
import SwiftData

@main
struct MaestroCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "maestro",
        abstract: "CLI for Maestro project management and agent orchestration",
        version: "1.0.0",
        subcommands: [
            ProjectCommand.self,
            TaskCommand.self,
            RunCommand.self,
            ImportCommand.self,
            ExportCommand.self,
        ]
    )
}

struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Path to database file (overrides default store location)")
    var dbPath: String?

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Flag(name: .long, help: "Minimal output (IDs only)")
    var quiet: Bool = false

    func makeContext() throws -> ModelContext {
        let container = try MaestroStore.makeContainer(dbPath: dbPath)
        return ModelContext(container)
    }
}
