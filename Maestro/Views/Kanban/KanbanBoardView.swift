import SwiftUI
import SwiftData
import MaestroCore

struct KanbanBoardView: View {
    @Bindable var project: Project
    @Query private var tasks: [ProjectTask]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.isDarkerMode) private var isDarkerMode
    @State private var showingNewTask = false
    @State private var newTaskColumn: KanbanColumn?
    @State private var selectedTask: ProjectTask?
    @State private var claudeMDExists: Bool = true  // default true to avoid flash
    @State private var showingNewColumn = false
    @State private var columnDropTargetIndex: Int?
    var onNavigateToRun: ((String) -> Void)?
    var onNavigateToSettings: (() -> Void)?

    init(project: Project, onNavigateToRun: ((String) -> Void)? = nil, onNavigateToSettings: (() -> Void)? = nil) {
        self.project = project
        self.onNavigateToRun = onNavigateToRun
        self.onNavigateToSettings = onNavigateToSettings
        let projectId = project.id
        _tasks = Query(
            filter: #Predicate<ProjectTask> { $0.project?.id == projectId && $0.isArchived == false },
            sort: [SortDescriptor(\.order)]
        )
    }

    private var sortedColumns: [KanbanColumn] {
        project.customColumns.sorted { $0.order < $1.order }
    }

    private func tasksForColumn(_ column: KanbanColumn) -> [ProjectTask] {
        tasks.filter { task in
            if !task.columnId.isEmpty {
                return task.columnId == column.id
            }
            // Fallback for legacy tasks without columnId: match by mapped status
            if let mappedStatus = column.mappedStatus {
                return task.statusRaw == mappedStatus
            }
            return false
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                columnDropZone(at: 0)

                ForEach(Array(sortedColumns.enumerated()), id: \.element.id) { index, column in
                    KanbanColumnView(
                        column: column,
                        tasks: tasksForColumn(column),
                        allTasks: tasks,
                        project: project,
                        selectedTask: $selectedTask,
                        onAddTask: { newTaskColumn = column; showingNewTask = true },
                        onColumnChanged: { updated in
                            updateColumn(updated)
                        },
                        onColumnDeleted: sortedColumns.count > 1 ? {
                            deleteColumn(column)
                        } : nil,
                        onMoveLeft: index > 0 ? {
                            moveColumn(column, toIndex: index - 1)
                        } : nil,
                        onMoveRight: index < sortedColumns.count - 1 ? {
                            moveColumn(column, toIndex: index + 1)
                        } : nil,
                        onColumnDroppedOnMe: { draggedColumnId in
                            moveColumnBefore(draggedColumnId, beforeColumnId: column.id)
                        }
                    )

                    columnDropZone(at: index + 1)
                }

                // Add column button
                Button { showingNewColumn = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.title3)
                        Text("Add Column")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 280, height: 100)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
                            .foregroundStyle(.quaternary)
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingNewColumn) {
                    NewColumnPopover(project: project, isPresented: $showingNewColumn)
                }
            }
            .padding()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedTask = nil
        }
        .background(Color.windowBackground(darker: isDarkerMode))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if !claudeMDExists && !project.workspaceRoot.isEmpty {
                    Button {
                        onNavigateToSettings?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("Agents don't know this project yet — Set up CLAUDE.md")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { showingNewTask = true }) {
                    Label("New Task", systemImage: "plus")
                }
            }
        }
        .navigationTitle(project.name)
        .sheet(isPresented: $showingNewTask) {
            NewTaskSheet(project: project, initialColumn: newTaskColumn)
        }
        .overlay(alignment: .trailing) {
            if let task = selectedTask {
                TaskDetailView(task: task, onDismiss: { selectedTask = nil }, onNavigateToRun: onNavigateToRun)
                    .frame(width: 350)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 0))
                    .shadow(color: .black.opacity(0.2), radius: 8, x: -2)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedTask != nil)
        .task(id: project.id) {
            claudeMDExists = !project.workspaceRoot.isEmpty &&
                FileManager.default.fileExists(atPath: "\(project.workspaceRoot)/CLAUDE.md")
        }
        .onChange(of: project.workspaceRoot) {
            claudeMDExists = !project.workspaceRoot.isEmpty &&
                FileManager.default.fileExists(atPath: "\(project.workspaceRoot)/CLAUDE.md")
        }
        .onExitCommand {
            selectedTask = nil
        }
        .onDeleteCommand {
            if let task = selectedTask {
                selectedTask = nil
                modelContext.delete(task)
            }
        }
    }

    @ViewBuilder
    private func columnDropZone(at index: Int) -> some View {
        let active = columnDropTargetIndex == index

        RoundedRectangle(cornerRadius: 8)
            .fill(active ? Color.accentColor.opacity(0.15) : Color.clear)
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                }
            }
            .frame(width: active ? 80 : 16, height: 200)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { droppedIds, _ in
                handleColumnDrop(droppedIds, at: index)
            } isTargeted: { targeted in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    if targeted {
                        columnDropTargetIndex = index
                    } else if columnDropTargetIndex == index {
                        columnDropTargetIndex = nil
                    }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: active)
    }

    private func handleColumnDrop(_ droppedIds: [String], at index: Int) -> Bool {
        guard let droppedId = droppedIds.first,
              droppedId.hasPrefix("column:") else {
            columnDropTargetIndex = nil
            return false
        }

        let columnId = String(droppedId.dropFirst("column:".count))
        var columns = sortedColumns

        guard let sourceIndex = columns.firstIndex(where: { $0.id == columnId }) else {
            columnDropTargetIndex = nil
            return false
        }

        // No-op if dropping in the same position
        guard sourceIndex != index && sourceIndex + 1 != index else {
            columnDropTargetIndex = nil
            return false
        }

        let column = columns.remove(at: sourceIndex)
        var targetIndex = index
        if sourceIndex < index {
            targetIndex -= 1
        }
        targetIndex = min(targetIndex, columns.count)
        columns.insert(column, at: targetIndex)

        for i in columns.indices {
            columns[i].order = i
        }

        project.customColumns = columns
        try? modelContext.save()

        columnDropTargetIndex = nil
        return true
    }

    private func moveColumn(_ column: KanbanColumn, toIndex targetIndex: Int) {
        var columns = sortedColumns
        guard let sourceIndex = columns.firstIndex(where: { $0.id == column.id }) else { return }

        let moved = columns.remove(at: sourceIndex)
        columns.insert(moved, at: targetIndex)

        for i in columns.indices {
            columns[i].order = i
        }

        project.customColumns = columns
        try? modelContext.save()
    }

    private func moveColumnBefore(_ draggedColumnId: String, beforeColumnId: String) {
        var columns = sortedColumns
        guard let sourceIndex = columns.firstIndex(where: { $0.id == draggedColumnId }) else { return }
        let moved = columns.remove(at: sourceIndex)
        guard let targetIndex = columns.firstIndex(where: { $0.id == beforeColumnId }) else {
            columns.append(moved)
            for i in columns.indices { columns[i].order = i }
            project.customColumns = columns
            try? modelContext.save()
            return
        }
        columns.insert(moved, at: targetIndex)
        for i in columns.indices { columns[i].order = i }
        project.customColumns = columns
        try? modelContext.save()
    }

    private func updateColumn(_ updated: KanbanColumn) {
        var columns = project.customColumns
        if let idx = columns.firstIndex(where: { $0.id == updated.id }) {
            columns[idx] = updated
            project.customColumns = columns
            try? modelContext.save()
        }
    }

    private func deleteColumn(_ column: KanbanColumn) {
        var columns = project.customColumns
        guard columns.count > 1 else { return }
        let firstOther = columns.first { $0.id != column.id }
        // Move tasks in deleted column to the first remaining column
        for task in tasksForColumn(column) {
            task.columnId = firstOther?.id ?? ""
            if let status = firstOther?.taskStatus {
                task.status = status
            }
        }
        columns.removeAll { $0.id == column.id }
        project.customColumns = columns
        try? modelContext.save()
    }
}

// MARK: - New Column Popover

private struct NewColumnPopover: View {
    let project: Project
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var selectedColor = "systemBlue"
    @State private var selectedStatus: TaskStatus?

    private let colors: [(String, Color)] = [
        ("systemBlue", .blue),
        ("systemOrange", .orange),
        ("systemPurple", .purple),
        ("systemGreen", .green),
        ("systemRed", .red),
        ("systemTeal", .teal),
        ("systemYellow", .yellow),
        ("systemPink", .pink),
        ("systemGray", .gray),
        ("systemIndigo", .indigo),
        ("systemMint", .mint),
        ("systemCyan", .cyan),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Column")
                .font(.headline)

            TextField("Column name", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Color")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 6), spacing: 8) {
                    ForEach(colors, id: \.0) { colorName, color in
                        Circle()
                            .fill(color)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .strokeBorder(.white, lineWidth: selectedColor == colorName ? 2.5 : 0)
                            )
                            .shadow(color: selectedColor == colorName ? color.opacity(0.5) : .clear, radius: 3)
                            .onTapGesture { selectedColor = colorName }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Mapped Status")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedStatus) {
                    Text("None").tag(TaskStatus?.none)
                    ForEach(TaskStatus.allCases) { s in
                        Text(s.rawValue).tag(TaskStatus?.some(s))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            HStack {
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Create") {
                    let columns = project.customColumns
                    let newOrder = (columns.map(\.order).max() ?? -1) + 1
                    let newColumn = KanbanColumn(
                        name: name,
                        color: selectedColor,
                        order: newOrder,
                        mappedStatus: selectedStatus?.rawValue
                    )
                    var updated = columns
                    updated.append(newColumn)
                    project.customColumns = updated
                    try? modelContext.save()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
