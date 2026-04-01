import SwiftUI
import SwiftData
import MaestroCore

struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let project: Project
    var initialColumn: KanbanColumn?

    @State private var title = ""
    @State private var description = ""
    @State private var priority: Priority = .medium
    @State private var status: TaskStatus = .todo
    @State private var dueDate: Date? = nil
    @State private var hasDueDate = false
    @State private var useWorktree: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            Text("New Task")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("Task Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $description)
                .font(.body)
                .frame(height: 100)
                .border(Color(nsColor: .separatorColor), width: 0.5)
                .cornerRadius(4)

            HStack {
                Picker("Priority", selection: $priority) {
                    ForEach(Priority.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }

                Picker("Status", selection: $status) {
                    ForEach(TaskStatus.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
            }

            Toggle("Due Date", isOn: $hasDueDate)
            if hasDueDate {
                DatePicker("Due", selection: Binding(
                    get: { dueDate ?? Date() },
                    set: { dueDate = $0 }
                ), displayedComponents: .date)
            }

            Toggle("Use dedicated git worktree", isOn: $useWorktree)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Create") {
                    let task = ProjectTask(title: title, description: description, project: project)
                    task.priority = priority
                    task.status = status
                    let targetColumnId: String
                    if let col = initialColumn,
                       col.order < (project.columnForStatus(.inProgress)?.order ?? Int.max) {
                        targetColumnId = col.id
                    } else {
                        targetColumnId = project.columnForStatus(status)?.id ?? project.customColumns.first?.id ?? ""
                    }
                    task.columnId = targetColumnId
                    task.dueDate = hasDueDate ? (dueDate ?? Date()) : nil
                    task.useWorktree = useWorktree
                    project.assignTicketNumber(to: task)

                    // Place new task at the top of its column
                    let columnTasks = (project.tasks ?? []).filter { $0.columnId == targetColumnId }
                    for existing in columnTasks {
                        existing.order += 1
                    }
                    task.order = 0

                    modelContext.insert(task)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450)
        .onAppear {
            useWorktree = project.defaultUseWorktree
            if let col = initialColumn {
                let inProgressOrder = project.columnForStatus(.inProgress)?.order ?? Int.max
                if col.order < inProgressOrder, let taskStatus = col.taskStatus {
                    status = taskStatus
                }
            }
        }
    }
}
