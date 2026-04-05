import SwiftUI
import MaestroCore

struct TaskCardView: View {
    let task: ProjectTask
    var isSelected: Bool = false
    @Environment(AgentOrchestrator.self) private var orchestrator
    @Environment(\.isDarkerMode) private var isDarkerMode

    private var pendingPermissionCount: Int {
        guard let runner = orchestrator.getRunner(for: task.id) else { return 0 }
        return runner.pendingPermissions.filter {
            if case .pending = $0.resolution { return true }
            return false
        }.count
    }

    var priorityColor: Color {
        switch task.priority {
        case .low: return Color(red: 0.74, green: 0.74, blue: 0.76)
        case .medium: return Color(red: 0.0, green: 0.63, blue: 1.0)
        case .high: return Color(red: 1.0, green: 0.77, blue: 0.0)
        case .critical: return Color(red: 1.0, green: 0.31, blue: 0.25)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if task.ticketNumber > 0 {
                        Text(task.ticketDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(task.title)
                        .font(.system(.body, weight: .medium))
                        .lineLimit(2)
                }
                Spacer()
                if task.isAgentRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !task.taskDescription.isEmpty {
                Text(task.taskDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                // Priority badge
                Text(task.priority.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(priorityColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(priorityColor)

                // Worktree indicator
                if task.useWorktree {
                    Image(systemName: task.hasMergeConflict ? "exclamationmark.triangle.fill" : "arrow.triangle.branch")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            (task.hasMergeConflict ? Color.red : Color.cyan).opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(task.hasMergeConflict ? .red : .cyan)
                        .help(task.hasMergeConflict ? "Branch has merge conflicts" : "Worktree: maestro/task-\(task.id.prefix(8))…")
                }

                Spacer()

                if pendingPermissionCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.orange)
                        Text("\(pendingPermissionCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                    }
                    .font(.caption)
                }

                // Agent status indicator
                if let run = task.latestRun {
                    HStack(spacing: 4) {
                        switch run.status {
                        case .running:
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.orange)
                        case .completed:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failed:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        case .cancelled:
                            Image(systemName: "stop.circle.fill")
                                .foregroundStyle(.gray)
                        default:
                            EmptyView()
                        }
                    }
                    .font(.caption)
                }

                if let due = task.dueDate {
                    Text(due, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.windowBackground(darker: isDarkerMode))
                .shadow(color: .black.opacity(isSelected ? 0.15 : 0.06), radius: isSelected ? 4 : 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
    }
}
