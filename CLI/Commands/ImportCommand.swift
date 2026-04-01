import ArgumentParser
import Foundation
import MaestroCore
import SwiftData

struct ImportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import tasks from a JSON file"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Path to JSON file")
    var file: String

    @Option(name: .long, help: "Target project name or ID")
    var project: String

    func run() throws {
        let context = try global.makeContext()
        let proj = try Resolver.resolveProject(project, in: context)

        let url = URL(fileURLWithPath: file)
        let data = try Data(contentsOf: url)

        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ValidationError("Expected JSON array of task objects")
        }

        var created = 0

        for item in items {
            guard let title = item["title"] as? String, !title.isEmpty else {
                continue
            }

            let desc = item["description"] as? String ?? ""
            let task = ProjectTask(title: title, description: desc, project: proj)

            if let statusStr = item["status"] as? String,
               let status = TaskStatus.fromCLI(statusStr) {
                task.status = status
            }

            if let priorityStr = item["priority"] as? String,
               let priority = Priority.fromCLI(priorityStr) {
                task.priority = priority
            }

            if let dueStr = item["due"] as? String ?? item["dueDate"] as? String {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                if let date = fmt.date(from: dueStr) {
                    task.dueDate = date
                }
            }

            // Assign ticket number
            proj.assignTicketNumber(to: task)

            // Assign column and place at top
            let targetColumnId = proj.columnForStatus(task.status)?.id ?? proj.customColumns.first?.id ?? ""
            task.columnId = targetColumnId
            let columnTasks = (proj.tasks ?? []).filter { $0.columnId == targetColumnId }
            for existing in columnTasks {
                existing.order += 1
            }
            task.order = 0

            context.insert(task)
            created += 1
        }

        try context.save()

        if global.json {
            print(JSONFormatter.format(["imported": String(created), "project": proj.name]))
        } else if global.quiet {
            print(created)
        } else {
            print("Imported \(created) tasks into project '\(proj.name)'")
        }
    }
}
