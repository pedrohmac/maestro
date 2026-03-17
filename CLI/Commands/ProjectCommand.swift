import ArgumentParser
import Foundation
import MaestroCore
import SwiftData

struct ProjectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "project",
        abstract: "Manage projects",
        subcommands: [List.self, Create.self, Show.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List all projects")

        @OptionGroup var global: GlobalOptions

        func run() throws {
            let context = try global.makeContext()
            let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.name)])
            let projects = try context.fetch(descriptor)

            if projects.isEmpty {
                if !global.quiet {
                    print("No projects found.")
                }
                return
            }

            if global.json {
                let items = projects.map { p in
                    [
                        "id": p.id,
                        "name": p.name,
                        "workspace": p.workspaceRoot,
                        "strategy": p.workspaceStrategy.cliName,
                        "dispatch": p.dispatchMode.cliName,
                        "tasks": String(p.tasks?.count ?? 0),
                    ]
                }
                print(JSONFormatter.format(items))
                return
            }

            if global.quiet {
                for p in projects { print(p.id) }
                return
            }

            let rows = projects.map { p in
                [
                    p.id.prefix(8).description,
                    p.name,
                    p.workspaceStrategy.cliName,
                    p.dispatchMode.cliName,
                    "\(p.tasks?.filter { !$0.isArchived }.count ?? 0) tasks",
                ]
            }
            TableFormatter.print(
                headers: ["ID", "NAME", "STRATEGY", "DISPATCH", "TASKS"],
                rows: rows
            )
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a new project")

        @OptionGroup var global: GlobalOptions

        @Option(name: .long, help: "Project name")
        var name: String

        @Option(name: .long, help: "Workspace root path")
        var workspace: String

        @Option(name: .long, help: "Workspace strategy: shared or isolated")
        var strategy: String?

        @Option(name: .long, help: "Dispatch mode: manual or auto")
        var dispatch: String?

        func run() throws {
            let context = try global.makeContext()

            let project = Project(name: name, workspaceRoot: workspace)

            if let strategy = strategy {
                guard let ws = WorkspaceStrategy.fromCLI(strategy) else {
                    throw ValidationError("Invalid strategy '\(strategy)'. Use: shared, isolated")
                }
                project.workspaceStrategy = ws
            }

            if let dispatch = dispatch {
                guard let dm = DispatchMode.fromCLI(dispatch) else {
                    throw ValidationError("Invalid dispatch mode '\(dispatch)'. Use: manual, auto")
                }
                project.dispatchMode = dm
            }

            context.insert(project)
            try context.save()

            if global.json {
                let item: [String: String] = [
                    "id": project.id,
                    "name": project.name,
                    "workspace": project.workspaceRoot,
                ]
                print(JSONFormatter.format(item))
            } else if global.quiet {
                print(project.id)
            } else {
                print("Created project '\(project.name)' (\(project.id.prefix(8)))")
            }
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show project details")

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Project name or ID")
        var nameOrId: String

        func run() throws {
            let context = try global.makeContext()
            let project = try Resolver.resolveProject(nameOrId, in: context)

            if global.json {
                let activeTasks = project.tasks?.filter { !$0.isArchived } ?? []
                let item: [String: Any] = [
                    "id": project.id,
                    "name": project.name,
                    "description": project.projectDescription,
                    "workspace": project.workspaceRoot,
                    "strategy": project.workspaceStrategy.cliName,
                    "dispatch": project.dispatchMode.cliName,
                    "maxConcurrentAgents": project.maxConcurrentAgents,
                    "maxTurns": project.maxTurns,
                    "allowedTools": project.defaultAllowedTools,
                    "taskCount": activeTasks.count,
                ]
                print(JSONFormatter.formatAny(item))
                return
            }

            if global.quiet {
                print(project.id)
                return
            }

            let activeTasks = project.tasks?.filter { !$0.isArchived } ?? []
            let byStatus = Dictionary(grouping: activeTasks) { $0.status }

            print("Project: \(project.name)")
            print("ID:      \(project.id)")
            if !project.projectDescription.isEmpty {
                print("Desc:    \(project.projectDescription)")
            }
            print("Root:    \(project.workspaceRoot)")
            print("Strategy: \(project.workspaceStrategy.rawValue)")
            print("Dispatch: \(project.dispatchMode.rawValue)")
            print("Agents:  max \(project.maxConcurrentAgents) concurrent, \(project.maxTurns) turns")
            print("Tools:   \(project.defaultAllowedTools)")
            if let budget = project.maxBudgetUSD {
                print("Budget:  $\(String(format: "%.2f", budget))")
            }
            print("")
            print("Tasks: \(activeTasks.count) active")
            for status in TaskStatus.allCases {
                let count = byStatus[status]?.count ?? 0
                if count > 0 {
                    print("  \(status.rawValue): \(count)")
                }
            }
        }
    }
}
