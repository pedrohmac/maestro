import SwiftUI
import SwiftData
import MaestroCore

// MARK: - Project Health

private enum ProjectHealth {
    case building
    case healthy
    case broken
    case idle

    var label: String {
        switch self {
        case .building: return "Building"
        case .healthy: return "Healthy"
        case .broken: return "Build Broken"
        case .idle: return "No builds yet"
        }
    }

    var icon: String {
        switch self {
        case .building: return "hammer.fill"
        case .healthy: return "checkmark.seal.fill"
        case .broken: return "exclamationmark.triangle.fill"
        case .idle: return "moon.zzz.fill"
        }
    }

    var color: Color {
        switch self {
        case .building: return .orange
        case .healthy: return .green
        case .broken: return .red
        case .idle: return .secondary
        }
    }
}

// MARK: - Timeline Event

private struct TimelineEvent: Identifiable {
    let id: String
    let date: Date
    let kind: Kind
    let title: String
    let ticketDisplay: String
    let detail: String?

    enum Kind {
        case taskCreated
        case taskStarted
        case taskCompleted
        case agentCompleted
        case agentFailed

        var icon: String {
            switch self {
            case .taskCreated: return "plus.circle.fill"
            case .taskStarted: return "play.circle.fill"
            case .taskCompleted: return "checkmark.circle.fill"
            case .agentCompleted: return "bolt.circle.fill"
            case .agentFailed: return "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .taskCreated: return .blue
            case .taskStarted: return .orange
            case .taskCompleted: return .green
            case .agentCompleted: return .teal
            case .agentFailed: return .red
            }
        }

        var verb: String {
            switch self {
            case .taskCreated: return "Created"
            case .taskStarted: return "Started"
            case .taskCompleted: return "Completed"
            case .agentCompleted: return "Agent finished"
            case .agentFailed: return "Agent failed on"
            }
        }
    }
}

// MARK: - Timeline Day

private struct TimelineDay: Identifiable {
    let id: Int
    let date: Date
    let events: [TimelineEvent]

    var dayLabel: String {
        "Day \(id + 1)"
    }

    var dateLabel: String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

// MARK: - View

struct ProjectTimelineView: View {
    @Bindable var project: Project
    @State private var timelineDays: [TimelineDay] = []
    @State private var health: ProjectHealth = .idle

    var body: some View {
        VStack(spacing: 0) {
            healthBanner

            if timelineDays.isEmpty {
                ContentUnavailableView(
                    "No Activity Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Create and work on tasks to build your project's story.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(timelineDays) { day in
                            daySection(day)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("\(project.name) — Timeline")
        .onAppear { refresh() }
        .onChange(of: project.tasks) { refresh() }
    }

    // MARK: - Health Banner

    private var healthBanner: some View {
        HStack(spacing: 8) {
            if health == .building {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: health.icon)
                    .foregroundStyle(health.color)
            }

            Text(health.label)
                .font(.system(size: 13, weight: .medium))

            if health == .broken {
                Text("— latest agent run failed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(healthDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(health.color.opacity(0.08))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var healthDetail: String {
        let tasks = project.tasks ?? []
        let active = tasks.filter { !$0.isArchived }
        let done = active.filter { $0.status == .done }.count
        let total = active.count
        if total == 0 { return "" }
        return "\(done)/\(total) tasks completed"
    }

    // MARK: - Day Section

    @ViewBuilder
    private func daySection(_ day: TimelineDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(day.dayLabel)
                    .font(.system(size: 15, weight: .semibold))
                Text(day.dateLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
            .padding(.top, timelineDays.first?.id == day.id ? 0 : 20)

            ForEach(Array(day.events.enumerated()), id: \.element.id) { index, event in
                let isLastGlobal = (timelineDays.last?.id == day.id) && (index == day.events.count - 1)
                eventRow(event, isLast: isLastGlobal)
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ event: TimelineEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline connector
            VStack(spacing: 0) {
                Circle()
                    .fill(event.kind.color)
                    .frame(width: 10, height: 10)

                if !isLast {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 10)

            // Event content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: event.kind.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(event.kind.color)

                    Text(event.kind.verb)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    if !event.ticketDisplay.isEmpty {
                        Text(event.ticketDisplay)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(event.title)
                    .font(.system(size: 13))

                if let detail = event.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(event.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 14)
        }
        .padding(.leading, 8)
    }

    // MARK: - Data

    private func refresh() {
        let tasks = (project.tasks ?? []).filter { !$0.isArchived }

        var events: [TimelineEvent] = []

        for task in tasks {
            events.append(TimelineEvent(
                id: "created-\(task.id)",
                date: task.createdDate,
                kind: .taskCreated,
                title: task.title,
                ticketDisplay: task.ticketDisplay,
                detail: nil
            ))

            if let startDate = task.startDate {
                events.append(TimelineEvent(
                    id: "started-\(task.id)",
                    date: startDate,
                    kind: .taskStarted,
                    title: task.title,
                    ticketDisplay: task.ticketDisplay,
                    detail: nil
                ))
            }

            if let completedDate = task.completedDate {
                events.append(TimelineEvent(
                    id: "completed-\(task.id)",
                    date: completedDate,
                    kind: .taskCompleted,
                    title: task.title,
                    ticketDisplay: task.ticketDisplay,
                    detail: nil
                ))
            }

            for run in (task.agentRuns ?? []) {
                guard let completedAt = run.completedAt else { continue }
                let kind: TimelineEvent.Kind = run.status == .completed ? .agentCompleted : .agentFailed
                var detailParts: [String] = []
                detailParts.append(run.durationFormatted)
                if let cost = run.costUSD {
                    detailParts.append(String(format: "$%.2f", cost))
                }
                events.append(TimelineEvent(
                    id: "run-\(run.id)",
                    date: completedAt,
                    kind: kind,
                    title: task.title,
                    ticketDisplay: task.ticketDisplay,
                    detail: detailParts.joined(separator: " · ")
                ))
            }
        }

        events.sort { $0.date < $1.date }

        let calendar = Calendar.current
        let projectStart = calendar.startOfDay(for: project.createdDate)

        var dayMap: [Int: [TimelineEvent]] = [:]
        for event in events {
            let dayNumber = calendar.dateComponents([.day], from: projectStart, to: calendar.startOfDay(for: event.date)).day ?? 0
            dayMap[max(0, dayNumber), default: []].append(event)
        }

        timelineDays = dayMap.map { dayNumber, dayEvents in
            let dayDate = calendar.date(byAdding: .day, value: dayNumber, to: projectStart) ?? projectStart
            return TimelineDay(id: dayNumber, date: dayDate, events: dayEvents)
        }.sorted { $0.id < $1.id }

        // Compute health
        let allRuns = tasks.flatMap { $0.agentRuns ?? [] }
        if allRuns.contains(where: { $0.status == .running }) {
            health = .building
        } else if let latestCompleted = allRuns
            .filter({ $0.completedAt != nil })
            .max(by: { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }) {
            health = latestCompleted.status == .failed ? .broken : .healthy
        } else {
            health = .idle
        }
    }
}
