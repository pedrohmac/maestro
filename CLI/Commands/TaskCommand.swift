import ArgumentParser
import Foundation
import MaestroCore
import SwiftData

struct TaskCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "task",
        abstract: "Manage tasks",
        subcommands: [
            List.self, Create.self, Show.self,
            Update.self, Archive.self, Comment.self,
        ]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List tasks")

        @OptionGroup var global: GlobalOptions

        @Option(name: .long, help: "Filter by project name")
        var project: String?

        @Option(name: .long, help: "Filter by status (comma-separated: todo,in-progress,review,done)")
        var status: String?

        @Option(name: .long, help: "Filter by priority (comma-separated: low,medium,high,critical)")
        var priority: String?

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

            // Filter by status
            if let statusFilter = status {
                let statuses = statusFilter.split(separator: ",").compactMap {
                    TaskStatus.fromCLI(String($0).trimmingCharacters(in: .whitespaces))
                }
                if !statuses.isEmpty {
                    tasks = tasks.filter { statuses.contains($0.status) }
                }
            }

            // Filter by priority
            if let priorityFilter = priority {
                let priorities = priorityFilter.split(separator: ",").compactMap {
                    Priority.fromCLI(String($0).trimmingCharacters(in: .whitespaces))
                }
                if !priorities.isEmpty {
                    tasks = tasks.filter { priorities.contains($0.priority) }
                }
            }

            tasks.sort {
                if $0.status.sortOrder != $1.status.sortOrder {
                    return $0.status.sortOrder < $1.status.sortOrder
                }
                return $0.priority.sortOrder > $1.priority.sortOrder
            }

            if tasks.isEmpty {
                if !global.quiet { print("No tasks found.") }
                return
            }

            if global.json {
                let items = tasks.map { t in
                    var dict: [String: String] = [
                        "id": t.id,
                        "ticketNumber": String(t.ticketNumber),
                        "title": t.title,
                        "status": t.status.cliName,
                        "priority": t.priority.cliName,
                        "project": t.project?.name ?? "",
                    ]
                    if let due = t.dueDate {
                        dict["dueDate"] = ISO8601DateFormatter().string(from: due)
                    }
                    return dict
                }
                print(JSONFormatter.format(items))
                return
            }

            if global.quiet {
                for t in tasks { print(t.id) }
                return
            }

            let rows = tasks.map { t in
                let dueStr: String
                if let due = t.dueDate {
                    let fmt = DateFormatter()
                    fmt.dateFormat = "yyyy-MM-dd"
                    dueStr = fmt.string(from: due)
                } else {
                    dueStr = "-"
                }

                return [
                    t.ticketDisplay,
                    String(t.id.prefix(8)),
                    t.status.cliName,
                    t.priority.cliName,
                    String(t.title.prefix(40)),
                    t.project?.name ?? "-",
                    dueStr,
                ]
            }

            TableFormatter.print(
                headers: ["#", "ID", "STATUS", "PRIORITY", "TITLE", "PROJECT", "DUE"],
                rows: rows
            )
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a new task")

        @OptionGroup var global: GlobalOptions

        @Option(name: .long, help: "Project name or ID")
        var project: String

        @Option(name: .long, help: "Task title")
        var title: String

        @Option(name: .long, help: "Task description")
        var description: String?

        @Option(name: .long, help: "Priority: low, medium, high, critical")
        var priority: String?

        @Option(name: .long, help: "Status: todo, in-progress, review, done")
        var status: String?

        @Option(name: .long, help: "Due date (YYYY-MM-DD)")
        var due: String?

        func run() throws {
            let context = try global.makeContext()
            let proj = try Resolver.resolveProject(project, in: context)

            let task = ProjectTask(title: title, description: description ?? "", project: proj)

            if let priority = priority {
                guard let p = Priority.fromCLI(priority) else {
                    throw ValidationError("Invalid priority '\(priority)'. Use: low, medium, high, critical")
                }
                task.priority = p
            }

            if let status = status {
                guard let s = TaskStatus.fromCLI(status) else {
                    throw ValidationError("Invalid status '\(status)'. Use: todo, in-progress, review, done")
                }
                task.status = s
            }

            if let due = due {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                guard let date = fmt.date(from: due) else {
                    throw ValidationError("Invalid date '\(due)'. Use format: YYYY-MM-DD")
                }
                task.dueDate = date
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
            try context.save()

            if global.json {
                let item: [String: String] = [
                    "id": task.id,
                    "ticketNumber": String(task.ticketNumber),
                    "title": task.title,
                    "status": task.status.cliName,
                    "priority": task.priority.cliName,
                    "project": proj.name,
                ]
                print(JSONFormatter.format(item))
            } else if global.quiet {
                print(task.id)
            } else {
                print("Created task \(task.ticketDisplay) '\(task.title)' (\(task.id.prefix(8))) in project '\(proj.name)'")
            }
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show task details")

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Task ID (full or prefix)")
        var taskId: String

        func run() throws {
            let context = try global.makeContext()
            let task = try Resolver.resolveTask(taskId, in: context)

            if global.json {
                var dict: [String: Any] = [
                    "id": task.id,
                    "ticketNumber": task.ticketNumber,
                    "title": task.title,
                    "description": task.taskDescription,
                    "status": task.status.cliName,
                    "priority": task.priority.cliName,
                    "project": task.project?.name ?? "",
                    "createdDate": ISO8601DateFormatter().string(from: task.createdDate),
                    "isArchived": task.isArchived,
                ]
                if let start = task.startDate {
                    dict["startDate"] = ISO8601DateFormatter().string(from: start)
                }
                if let due = task.dueDate {
                    dict["dueDate"] = ISO8601DateFormatter().string(from: due)
                }
                if let completed = task.completedDate {
                    dict["completedDate"] = ISO8601DateFormatter().string(from: completed)
                }
                let runs = task.agentRuns?.count ?? 0
                dict["agentRunCount"] = runs
                let comments = task.comments?.count ?? 0
                dict["commentCount"] = comments
                print(JSONFormatter.formatAny(dict))
                return
            }

            if global.quiet {
                print(task.id)
                return
            }

            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "yyyy-MM-dd HH:mm"

            print("Task:     \(task.ticketDisplay) \(task.title)")
            print("ID:       \(task.id)")
            print("Status:   \(task.status.rawValue)")
            print("Priority: \(task.priority.rawValue)")
            print("Project:  \(task.project?.name ?? "-")")
            print("Created:  \(dateFmt.string(from: task.createdDate))")
            if let start = task.startDate {
                print("Started:  \(dateFmt.string(from: start))")
            }
            if let due = task.dueDate {
                print("Due:      \(dateFmt.string(from: due))")
            }
            if let completed = task.completedDate {
                print("Done:     \(dateFmt.string(from: completed))")
            }
            if !task.taskDescription.isEmpty {
                print("")
                print("Description:")
                print(task.taskDescription)
            }

            let runs = task.agentRuns ?? []
            if !runs.isEmpty {
                print("")
                print("Agent Runs: \(runs.count)")
                for run in runs.sorted(by: { $0.startedAt > $1.startedAt }).prefix(5) {
                    let costStr = run.costUSD.map { String(format: "$%.4f", $0) } ?? "-"
                    print("  \(run.id.prefix(8))  \(run.status.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0))  \(run.durationFormatted)  \(costStr)")
                }
            }

            let comments = task.comments ?? []
            if !comments.isEmpty {
                print("")
                print("Comments: \(comments.count)")
                for comment in comments.sorted(by: { $0.createdDate > $1.createdDate }).prefix(5) {
                    let preview = String(comment.body.prefix(60)).replacingOccurrences(of: "\n", with: " ")
                    print("  [\(comment.authorType.rawValue)] \(preview)")
                }
            }
        }
    }

    struct Update: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Update a task")

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Task ID (full or prefix)")
        var taskId: String

        @Option(name: .long, help: "New title")
        var title: String?

        @Option(name: .long, help: "New status: todo, in-progress, review, done")
        var status: String?

        @Option(name: .long, help: "New priority: low, medium, high, critical")
        var priority: String?

        @Option(name: .long, help: "New due date (YYYY-MM-DD)")
        var due: String?

        @Option(name: .long, help: "New description")
        var description: String?

        func run() throws {
            let context = try global.makeContext()
            let task = try Resolver.resolveTask(taskId, in: context)

            var changes: [String] = []

            if let title = title {
                task.title = title
                changes.append("title")
            }

            if let status = status {
                guard let s = TaskStatus.fromCLI(status) else {
                    throw ValidationError("Invalid status '\(status)'. Use: todo, in-progress, review, done")
                }
                task.status = s
                changes.append("status -> \(s.rawValue)")
            }

            if let priority = priority {
                guard let p = Priority.fromCLI(priority) else {
                    throw ValidationError("Invalid priority '\(priority)'. Use: low, medium, high, critical")
                }
                task.priority = p
                changes.append("priority -> \(p.rawValue)")
            }

            if let due = due {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                guard let date = fmt.date(from: due) else {
                    throw ValidationError("Invalid date '\(due)'. Use format: YYYY-MM-DD")
                }
                task.dueDate = date
                changes.append("due date")
            }

            if let description = description {
                task.taskDescription = description
                changes.append("description")
            }

            if changes.isEmpty {
                throw ValidationError("No changes specified. Use --title, --status, --priority, --due, or --description")
            }

            try context.save()

            if global.json {
                let item: [String: String] = [
                    "id": task.id,
                    "title": task.title,
                    "status": task.status.cliName,
                    "priority": task.priority.cliName,
                    "updated": changes.joined(separator: ", "),
                ]
                print(JSONFormatter.format(item))
            } else if global.quiet {
                print(task.id)
            } else {
                print("Updated task '\(task.title)' (\(task.id.prefix(8))): \(changes.joined(separator: ", "))")
            }
        }
    }

    struct Archive: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Archive a task")

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Task ID (full or prefix)")
        var taskId: String

        func run() throws {
            let context = try global.makeContext()
            let task = try Resolver.resolveTask(taskId, in: context)

            task.isArchived = true
            task.archivedDate = Date()
            try context.save()

            if global.json {
                print(JSONFormatter.format(["id": task.id, "archived": "true"]))
            } else if global.quiet {
                print(task.id)
            } else {
                print("Archived task '\(task.title)' (\(task.id.prefix(8)))")
            }
        }
    }

    struct Comment: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add a comment to a task")

        @OptionGroup var global: GlobalOptions

        @Argument(help: "Task ID (full or prefix)")
        var taskId: String

        @Option(name: .long, help: "Comment body")
        var body: String

        func run() throws {
            let context = try global.makeContext()
            let task = try Resolver.resolveTask(taskId, in: context)

            let comment = TaskComment(body: body, authorType: .user, task: task)
            context.insert(comment)
            try context.save()

            if global.json {
                print(JSONFormatter.format([
                    "id": comment.id,
                    "taskId": task.id,
                    "body": body,
                    "author": "user",
                ]))
            } else if global.quiet {
                print(comment.id)
            } else {
                print("Added comment to task '\(task.title)' (\(task.id.prefix(8)))")
            }
        }
    }
}
