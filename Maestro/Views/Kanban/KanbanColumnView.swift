import SwiftUI
import SwiftData
import MaestroCore

struct KanbanColumnView: View {
    let column: KanbanColumn
    let tasks: [ProjectTask]
    let allTasks: [ProjectTask]
    let project: Project
    @Binding var selectedTask: ProjectTask?
    var onAddTask: (() -> Void)?
    var onColumnChanged: ((KanbanColumn) -> Void)?
    var onColumnDeleted: (() -> Void)?
    var onMoveLeft: (() -> Void)?
    var onMoveRight: (() -> Void)?
    var onColumnDroppedOnMe: ((String) -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.isDarkerMode) private var isDarkerMode
    @Environment(AgentOrchestrator.self) private var orchestrator
    @State private var dropTargetIndex: Int?
    @State private var showClearConfirmation = false
    @State private var isRenaming = false
    @State private var editedName: String = ""
    @State private var showColorPicker = false
    @State private var showDeleteConfirmation = false
    @State private var isColumnDragTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column header
            HStack {
                Circle()
                    .fill(column.swiftUIColor)
                    .frame(width: 8, height: 8)
                if isRenaming {
                    TextField("Column name", text: $editedName, onCommit: {
                        var updated = column
                        updated.name = editedName
                        onColumnChanged?(updated)
                        isRenaming = false
                    })
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .frame(maxWidth: 140)
                    .onExitCommand {
                        isRenaming = false
                    }
                } else {
                    Text(column.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                Text("\(tasks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Spacer()
                if column.mappedStatus == TaskStatus.done.rawValue && !tasks.isEmpty {
                    Button(action: { showClearConfirmation = true }) {
                        Image(systemName: "archivebox")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Archive all done tasks")
                }
                if let onAddTask {
                    Button(action: onAddTask) {
                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isColumnDragTarget ? column.swiftUIColor.opacity(0.2) : Color.clear)
            )
            .overlay(alignment: .leading) {
                if isColumnDragTarget {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 4)
                }
            }
            .draggable("column:\(column.id)")
            .dropDestination(for: String.self) { droppedIds, _ in
                defer { isColumnDragTarget = false }
                guard let droppedId = droppedIds.first,
                      droppedId.hasPrefix("column:") else { return false }
                let columnId = String(droppedId.dropFirst("column:".count))
                guard columnId != column.id else { return false }
                onColumnDroppedOnMe?(columnId)
                return true
            } isTargeted: { targeted in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isColumnDragTarget = targeted
                }
            }
            .contextMenu {
                Button("Rename") {
                    editedName = column.name
                    isRenaming = true
                }
                Button("Change Color") {
                    showColorPicker = true
                }
                if onMoveLeft != nil || onMoveRight != nil {
                    Divider()
                }
                if let onMoveLeft {
                    Button("Move Left") { onMoveLeft() }
                }
                if let onMoveRight {
                    Button("Move Right") { onMoveRight() }
                }
                if onColumnDeleted != nil {
                    Divider()
                    Button("Delete Column", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }

            Divider()

            // Task cards
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    dropZone(at: 0)

                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        TaskCardView(task: task, isSelected: selectedTask?.id == task.id)
                            .padding(.horizontal, 8)
                            .overlay {
                                cardDropOverlay(at: index)
                            }
                            .draggable(task.id)
                            .onTapGesture {
                                selectedTask = task
                            }

                        dropZone(at: index + 1)
                    }
                }
                .padding(.vertical, 4)
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { droppedIds, _ in
                handleDrop(droppedIds, at: dropTargetIndex ?? tasks.count)
            } isTargeted: { targeted in
                if !targeted {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        dropTargetIndex = nil
                    }
                }
            }
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.controlBackground(darker: isDarkerMode))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(dropTargetIndex != nil ? column.swiftUIColor.opacity(0.6) : Color.clear, lineWidth: 2)
                )
        )
        .confirmationDialog("Archive all done tasks?", isPresented: $showClearConfirmation) {
            Button("Archive", role: .destructive) {
                for task in tasks {
                    task.isArchived = true
                    task.archivedDate = Date()
                }
                try? modelContext.save()
            }
        } message: {
            Text("Archived tasks will be hidden from the board.")
        }
        .confirmationDialog("Delete this column?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onColumnDeleted?()
            }
        } message: {
            Text("Tasks in this column will be moved to the first column.")
        }
        .popover(isPresented: $showColorPicker) {
            ColumnColorPicker(currentColor: column.color) { newColor in
                var updated = column
                updated.color = newColor
                onColumnChanged?(updated)
                showColorPicker = false
            }
        }
        .onChange(of: Set(tasks.map(\.id))) { oldIds, newIds in
            guard column.mappedStatus == TaskStatus.inProgress.rawValue,
                  project.dispatchMode == .auto,
                  !project.workspaceRoot.isEmpty else { return }
            let arrivals = newIds.subtracting(oldIds)
            for task in tasks where arrivals.contains(task.id) {
                orchestrator.runAgent(task: task, project: project)
            }
        }
    }

    @ViewBuilder
    private func dropZone(at index: Int) -> some View {
        let active = dropTargetIndex == index

        RoundedRectangle(cornerRadius: 6)
            .fill(active ? column.swiftUIColor.opacity(0.12) : Color.clear)
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(column.swiftUIColor.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                }
            }
            .frame(height: active ? 48 : 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { droppedIds, _ in
                handleDrop(droppedIds, at: index)
            } isTargeted: { targeted in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    if targeted {
                        dropTargetIndex = index
                    } else if dropTargetIndex == index {
                        dropTargetIndex = nil
                    }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: active)
    }

    @ViewBuilder
    private func cardDropOverlay(at index: Int) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { droppedIds, _ in
                    handleDrop(droppedIds, at: index)
                } isTargeted: { targeted in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        if targeted {
                            dropTargetIndex = index
                        } else if dropTargetIndex == index {
                            dropTargetIndex = nil
                        }
                    }
                }
            Color.clear
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { droppedIds, _ in
                    handleDrop(droppedIds, at: index + 1)
                } isTargeted: { targeted in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        if targeted {
                            dropTargetIndex = index + 1
                        } else if dropTargetIndex == index + 1 {
                            dropTargetIndex = nil
                        }
                    }
                }
        }
    }

    private func handleDrop(_ droppedIds: [String], at index: Int) -> Bool {
        guard let taskId = droppedIds.first,
              !taskId.hasPrefix("column:"),
              let task = allTasks.first(where: { $0.id == taskId }) else { return false }

        // Assign to this column
        task.columnId = column.id
        if let taskStatus = column.taskStatus {
            task.status = taskStatus
        }

        // Adjust index when moving within the same column downward
        var reorderedTasks = tasks.filter { $0.id != taskId }
        var adjustedIndex = index
        if let existingIndex = tasks.firstIndex(where: { $0.id == taskId }),
           existingIndex < index {
            adjustedIndex -= 1
        }
        let clampedIndex = min(adjustedIndex, reorderedTasks.count)
        reorderedTasks.insert(task, at: clampedIndex)

        for (i, t) in reorderedTasks.enumerated() {
            t.order = i
        }

        try? modelContext.save()

        dropTargetIndex = nil
        return true
    }
}

// MARK: - Color helpers

extension KanbanColumn {
    var swiftUIColor: Color {
        switch color {
        case "systemBlue": return .blue
        case "systemOrange": return .orange
        case "systemPurple": return .purple
        case "systemGreen": return .green
        case "systemRed": return .red
        case "systemTeal": return .teal
        case "systemYellow": return .yellow
        case "systemPink": return .pink
        case "systemGray": return .gray
        case "systemIndigo": return .indigo
        case "systemMint": return .mint
        case "systemCyan": return .cyan
        case "systemBrown": return .brown
        default: return .blue
        }
    }
}

// MARK: - Color picker popover

private struct ColumnColorPicker: View {
    let currentColor: String
    let onSelect: (String) -> Void

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
        VStack(alignment: .leading, spacing: 8) {
            Text("Column Color")
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 6), spacing: 8) {
                ForEach(colors, id: \.0) { name, color in
                    Circle()
                        .fill(color)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .strokeBorder(.white, lineWidth: currentColor == name ? 2.5 : 0)
                        )
                        .shadow(color: currentColor == name ? color.opacity(0.5) : .clear, radius: 3)
                        .onTapGesture { onSelect(name) }
                }
            }
        }
        .padding(12)
    }
}
