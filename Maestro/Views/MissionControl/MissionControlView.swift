import SwiftUI
import SwiftData
import MaestroCore

struct MissionControlView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AgentOrchestrator.self) private var orchestrator
    @Environment(\.isDarkerMode) private var isDarkerMode
    @Query(sort: \Project.createdDate, order: .reverse) private var projects: [Project]
    @State private var activityLimit: Int = 20
    @State private var cachedAgentRuns: [AgentRun] = []
    var isActive: Bool = true

    // MARK: - Aggregated Stats

    private var allTasks: [ProjectTask] {
        projects.flatMap { $0.tasks ?? [] }.filter { !$0.isArchived }
    }

    private var totalTasks: Int { allTasks.count }

    private var doneTasks: Int {
        allTasks.filter { $0.status == .done }.count
    }

    private var completionPercent: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(doneTasks) / Double(totalTasks) * 100
    }

    private var activeAgentCount: Int {
        orchestrator.activeRunners.count
    }

    private var totalSpend: Double {
        cachedAgentRuns.compactMap(\.costUSD).reduce(0, +)
    }

    private var bottleneckTasks: [ProjectTask] {
        let now = Date()
        return allTasks.filter { task in
            // Overdue: has a due date in the past and is not done
            if let due = task.dueDate, due < now, task.status != .done {
                return true
            }
            // Failed agent: latest run failed
            if task.latestRun?.status == .failed {
                return true
            }
            return false
        }
        .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var recentActivity: [AgentRun] {
        Array(cachedAgentRuns.prefix(activityLimit))
    }

    private func refreshAgentRuns() {
        var descriptor = FetchDescriptor<AgentRun>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        cachedAgentRuns = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statsRow
                projectsGrid
                if !bottleneckTasks.isEmpty {
                    bottlenecksSection
                }
                activityFeed
            }
            .padding(20)
        }
        .background(Color.windowBackground(darker: isDarkerMode))
        .toolbar {
            if isActive {
                ToolbarItem(placement: .automatic) {
                    globalAgentControls
                }
            }
        }
        .task {
            refreshAgentRuns()
        }
        .onChange(of: orchestrator.activeRunners.count) {
            refreshAgentRuns()
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 16) {
            StatCard(
                title: "Projects",
                value: "\(projects.count)",
                icon: "folder.fill",
                color: .blue
            )
            StatCard(
                title: "Tasks",
                value: "\(doneTasks)/\(totalTasks)",
                icon: "checkmark.square.fill",
                color: .green,
                subtitle: totalTasks > 0 ? String(format: "%.0f%% complete", completionPercent) : nil
            )
            StatCard(
                title: "Active Agents",
                value: "\(activeAgentCount)",
                icon: "bolt.fill",
                color: activeAgentCount > 0 ? .orange : .secondary
            )
            StatCard(
                title: "Total Spend",
                value: String(format: "$%.2f", totalSpend),
                icon: "dollarsign.circle.fill",
                color: .purple
            )
        }
    }

    // MARK: - Projects Grid

    private var projectsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Projects")
                .font(.title3)
                .fontWeight(.semibold)

            if projects.isEmpty {
                ContentUnavailableView("No Projects", systemImage: "folder", description: Text("Create a project to get started."))
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 500), spacing: 12)], spacing: 12) {
                    ForEach(projects, id: \.id) { project in
                        ProjectSummaryCard(project: project, orchestrator: orchestrator, isDarkerMode: isDarkerMode)
                    }
                }
            }
        }
    }

    // MARK: - Bottlenecks

    private var bottlenecksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Bottlenecks")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("\(bottleneckTasks.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 6) {
                ForEach(bottleneckTasks.prefix(10), id: \.id) { task in
                    BottleneckRow(task: task)
                }
            }
        }
    }

    // MARK: - Activity Feed

    private var activityFeed: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Activity")
                .font(.title3)
                .fontWeight(.semibold)

            if recentActivity.isEmpty {
                ContentUnavailableView("No Activity", systemImage: "bolt.slash", description: Text("Agent runs will appear here."))
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                VStack(spacing: 4) {
                    ForEach(recentActivity, id: \.id) { run in
                        ActivityRow(run: run)
                    }

                    if cachedAgentRuns.count > activityLimit {
                        Button {
                            activityLimit += 20
                        } label: {
                            Text("Load More...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    // MARK: - Global Agent Controls

    private var globalAgentControls: some View {
        HStack(spacing: 8) {
            if activeAgentCount > 0 {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("\(activeAgentCount) running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button(role: .destructive) {
                orchestrator.cancelAll()
            } label: {
                Label("Stop All Agents", systemImage: "stop.circle.fill")
            }
            .disabled(activeAgentCount == 0)
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Project Summary Card

private struct ProjectSummaryCard: View {
    let project: Project
    let orchestrator: AgentOrchestrator
    let isDarkerMode: Bool

    private var tasks: [ProjectTask] {
        (project.tasks ?? []).filter { !$0.isArchived }
    }

    private var doneTasks: Int {
        tasks.filter { $0.status == .done }.count
    }

    private var totalTasks: Int { tasks.count }

    private var completionFraction: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(doneTasks) / Double(totalTasks)
    }

    private var activeAgents: Int {
        let projectTaskIds = Set(tasks.map(\.id))
        return orchestrator.activeRunners.keys.filter { projectTaskIds.contains($0) }.count
    }

    private var projectSpend: Double {
        tasks.flatMap { $0.agentRuns ?? [] }
            .compactMap(\.costUSD)
            .reduce(0, +)
    }

    private var statusCounts: [(TaskStatus, Int)] {
        TaskStatus.allCases.compactMap { status in
            let count = tasks.filter { $0.status == status }.count
            return count > 0 ? (status, count) : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.headline)
                    if !project.projectDescription.isEmpty {
                        Text(project.projectDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if activeAgents > 0 {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        Text("\(activeAgents)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                    }
                }
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(.green)
                            .frame(width: geo.size.width * completionFraction, height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("\(doneTasks)/\(totalTasks) tasks")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%%", completionFraction * 100))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }

            // Status breakdown + spend
            HStack(spacing: 8) {
                ForEach(statusCounts, id: \.0) { status, count in
                    statusBadge(status: status, count: count)
                }
                Spacer()
                if projectSpend > 0 {
                    Text(String(format: "$%.2f", projectSpend))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.controlBackground(darker: isDarkerMode), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func statusBadge(status: TaskStatus, count: Int) -> some View {
        let color = statusColor(for: status)
        Text("\(count) \(status.rawValue)")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    private func statusColor(for status: TaskStatus) -> Color {
        switch status {
        case .todo: return .blue
        case .inProgress: return .orange
        case .review: return .purple
        case .done: return .green
        }
    }
}

// MARK: - Bottleneck Row

private struct BottleneckRow: View {
    let task: ProjectTask

    private var reason: String {
        if let due = task.dueDate, due < Date() {
            return "Overdue"
        }
        if task.latestRun?.status == .failed {
            return "Agent Failed"
        }
        return "Blocked"
    }

    private var reasonColor: Color {
        switch reason {
        case "Overdue": return .red
        case "Agent Failed": return .orange
        default: return .yellow
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(reason)
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(reasonColor.opacity(0.15), in: Capsule())
                .foregroundStyle(reasonColor)
                .frame(width: 90, alignment: .leading)

            if let projectName = task.project?.name {
                Text(projectName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                    .lineLimit(1)
            }

            HStack(spacing: 4) {
                if task.ticketNumber > 0 {
                    Text(task.ticketDisplay)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(task.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
            }

            Spacer()

            if let due = task.dueDate {
                Text(due, style: .date)
                    .font(.caption2)
                    .foregroundStyle(due < Date() ? .red : .secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Activity Row

private struct ActivityRow: View {
    let run: AgentRun

    private var statusIcon: String {
        switch run.status {
        case .running: return "bolt.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        case .timedOut: return "clock.badge.exclamationmark"
        case .queued: return "clock"
        case .rolledBack: return "arrow.uturn.backward.circle"
        }
    }

    private var statusColor: Color {
        switch run.status {
        case .running: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        case .timedOut: return .yellow
        case .queued: return .blue
        case .rolledBack: return .purple
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 16)

            // Project name
            if let projectName = run.task?.project?.name {
                Text(projectName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                    .lineLimit(1)
            }

            // Ticket + task title
            HStack(spacing: 4) {
                let ticketNum = run.task?.ticketNumber ?? run.ticketNumber
                if ticketNum > 0 {
                    Text("#\(ticketNum)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(run.task?.title ?? run.taskTitle)
                    .font(.system(size: 13))
                    .lineLimit(1)
            }

            Spacer()

            // Duration
            Text(run.durationFormatted)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            // Cost
            if let cost = run.costUSD {
                Text(String(format: "$%.4f", cost))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            } else {
                Text("")
                    .frame(width: 70)
            }

            // Relative time
            Text(run.relativeTimeFormatted)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .trailing)

            // Running indicator
            if run.status == .running {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
