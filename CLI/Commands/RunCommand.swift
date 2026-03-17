import ArgumentParser
import Foundation
import MaestroCore
import SwiftData

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "View agent runs",
        subcommands: [List.self, Show.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List agent runs")

        @OptionGroup var global: GlobalOptions

        @Option(name: .long, help: "Filter by project name")
        var project: String?

        @Option(name: .long, help: "Filter by status (comma-separated: queued,running,completed,failed,cancelled,timed-out)")
        var status: String?

        @Option(name: .long, help: "Maximum number of results")
        var limit: Int?

        func run() throws {
            let context = try global.makeContext()
            let descriptor = FetchDescriptor<AgentRun>(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            var runs = try context.fetch(descriptor)

            if let projectName = project {
                let proj = try Resolver.resolveProject(projectName, in: context)
                runs = runs.filter { $0.projectId == proj.id }
            }

            if let statusFilter = status {
                let statuses = statusFilter.split(separator: ",").compactMap {
                    RunStatus.fromCLI(String($0).trimmingCharacters(in: .whitespaces))
                }
                if !statuses.isEmpty {
                    runs = runs.filter { statuses.contains($0.status) }
                }
            }

            if let limit = limit {
                runs = Array(runs.prefix(limit))
            }

            if runs.isEmpty {
                if !global.quiet { print("No agent runs found.") }
                return
            }

            if global.json {
                let items = runs.map { r in
                    var dict: [String: String] = [
                        "id": r.id,
                        "taskTitle": r.taskTitle,
                        "status": r.status.cliName,
                        "startedAt": ISO8601DateFormatter().string(from: r.startedAt),
                        "duration": r.durationFormatted,
                    ]
                    if let cost = r.costUSD {
                        dict["cost"] = String(format: "%.4f", cost)
                    }
                    if let tokens = r.tokensUsed {
                        dict["tokens"] = String(tokens)
                    }
                    return dict
                }
                print(JSONFormatter.format(items))
                return
            }

            if global.quiet {
                for r in runs { print(r.id) }
                return
            }

            let rows = runs.map { r in
                let costStr = r.costUSD.map { String(format: "$%.4f", $0) } ?? "-"
                return [
                    String(r.id.prefix(8)),
                    r.status.cliName,
                    String(r.taskTitle.prefix(30)),
                    r.durationFormatted,
                    costStr,
                    r.relativeTimeFormatted,
                ]
            }

            TableFormatter.print(
                headers: ["ID", "STATUS", "TASK", "DURATION", "COST", "STARTED"],
                rows: rows
            )
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show agent run details")

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Run ID (full or prefix)")
        var runId: String

        func run() throws {
            let context = try global.makeContext()
            let agentRun = try Resolver.resolveRun(runId, in: context)

            if global.json {
                var dict: [String: Any] = [
                    "id": agentRun.id,
                    "taskTitle": agentRun.taskTitle,
                    "status": agentRun.status.cliName,
                    "startedAt": ISO8601DateFormatter().string(from: agentRun.startedAt),
                    "duration": agentRun.durationFormatted,
                    "projectId": agentRun.projectId,
                ]
                if let sessionId = agentRun.sessionId {
                    dict["sessionId"] = sessionId
                }
                if let cost = agentRun.costUSD {
                    dict["cost"] = cost
                }
                if let tokens = agentRun.tokensUsed {
                    dict["tokens"] = tokens
                }
                if let exitCode = agentRun.exitCode {
                    dict["exitCode"] = exitCode
                }
                if let completed = agentRun.completedAt {
                    dict["completedAt"] = ISO8601DateFormatter().string(from: completed)
                }
                print(JSONFormatter.formatAny(dict))
                return
            }

            if global.quiet {
                print(agentRun.id)
                return
            }

            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"

            print("Run:      \(agentRun.id)")
            print("Task:     \(agentRun.taskTitle)")
            print("Status:   \(agentRun.status.rawValue)")
            print("Started:  \(dateFmt.string(from: agentRun.startedAt))")
            if let completed = agentRun.completedAt {
                print("Ended:    \(dateFmt.string(from: completed))")
            }
            print("Duration: \(agentRun.durationFormatted)")
            if let sessionId = agentRun.sessionId {
                print("Session:  \(sessionId)")
            }
            if let tokens = agentRun.tokensUsed {
                print("Tokens:   \(tokens)")
            }
            if let cost = agentRun.costUSD {
                print("Cost:     $\(String(format: "%.4f", cost))")
            }
            if let exitCode = agentRun.exitCode {
                print("Exit:     \(exitCode)")
            }
            if !agentRun.log.isEmpty {
                print("")
                print("Log:")
                print(agentRun.log)
            }
        }
    }
}
