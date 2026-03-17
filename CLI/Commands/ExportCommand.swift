import ArgumentParser
import Foundation
import MaestroCore
import SwiftData

struct ExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export tasks as JSON or Markdown"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Project name or ID (exports all if omitted)")
    var project: String?

    @Option(name: .long, help: "Output format: json or md (default: json)")
    var format: String = "json"

    func run() throws {
        let context = try global.makeContext()

        var tasks: [ProjectTask]

        if let projectName = project {
            let proj = try Resolver.resolveProject(projectName, in: context)
            tasks = proj.tasks?.filter { !$0.isArchived } ?? []
        } else {
            let descriptor = FetchDescriptor<ProjectTask>()
            tasks = try context.fetch(descriptor).filter { !$0.isArchived }
        }

        tasks.sort { $0.createdDate < $1.createdDate }

        switch format.lowercased() {
        case "json":
            printJSON(tasks)
        case "md", "markdown":
            printMarkdown(tasks)
        default:
            throw ValidationError("Invalid format '\(format)'. Use: json, md")
        }
    }

    private func printJSON(_ tasks: [ProjectTask]) {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        let items: [[String: Any]] = tasks.map { t in
            var dict: [String: Any] = [
                "id": t.id,
                "title": t.title,
                "description": t.taskDescription,
                "status": t.status.cliName,
                "priority": t.priority.cliName,
                "project": t.project?.name ?? "",
                "createdDate": ISO8601DateFormatter().string(from: t.createdDate),
            ]
            if let due = t.dueDate {
                dict["dueDate"] = dateFmt.string(from: due)
            }
            if let start = t.startDate {
                dict["startDate"] = dateFmt.string(from: start)
            }
            return dict
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: items,
            options: [.prettyPrinted, .sortedKeys]
        ),
            let str = String(data: data, encoding: .utf8)
        {
            print(str)
        }
    }

    private func printMarkdown(_ tasks: [ProjectTask]) {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        let grouped = Dictionary(grouping: tasks) { $0.project?.name ?? "No Project" }

        for (projectName, projectTasks) in grouped.sorted(by: { $0.key < $1.key }) {
            print("# \(projectName)")
            print("")

            let byStatus = Dictionary(grouping: projectTasks) { $0.status }

            for status in TaskStatus.allCases {
                guard let statusTasks = byStatus[status], !statusTasks.isEmpty else { continue }

                print("## \(status.rawValue)")
                print("")
                for task in statusTasks {
                    let priorityTag = task.priority == .medium ? "" : " [\(task.priority.rawValue)]"
                    let dueTag = task.dueDate.map { " (due: \(dateFmt.string(from: $0)))" } ?? ""
                    print("- \(task.title)\(priorityTag)\(dueTag)")
                    if !task.taskDescription.isEmpty {
                        let preview = String(task.taskDescription.prefix(100))
                            .replacingOccurrences(of: "\n", with: " ")
                        print("  \(preview)")
                    }
                }
                print("")
            }
        }
    }
}
