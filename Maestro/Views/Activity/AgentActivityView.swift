import SwiftUI
import SwiftData
import MaestroCore

struct AgentActivityView: View {
    @Bindable var project: Project
    @Environment(AgentOrchestrator.self) private var orchestrator
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedRunId: String?
    @State private var historyLimit: Int = 10

    var activeRuns: [AgentRun] {
        let projectId = project.id
        let descriptor = FetchDescriptor<AgentRun>(
            predicate: #Predicate { $0.projectId == projectId && $0.statusRaw == "running" },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    var completedRuns: [AgentRun] {
        let projectId = project.id
        var descriptor = FetchDescriptor<AgentRun>(
            predicate: #Predicate { $0.projectId == projectId && $0.statusRaw != "running" && $0.statusRaw != "queued" },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = historyLimit + 1
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedRunId) {
                if !activeRuns.isEmpty {
                    Section("Active") {
                        ForEach(activeRuns, id: \.id) { run in
                            AgentRunRow(run: run, isActive: true)
                                .tag(run.id)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        if let taskId = run.task?.id {
                                            orchestrator.cancelAgent(taskId: taskId)
                                        }
                                    } label: {
                                        Label("Cancel", systemImage: "stop.circle")
                                    }
                                    Button(role: .destructive) {
                                        if selectedRunId == run.id {
                                            selectedRunId = nil
                                        }
                                        orchestrator.deleteRun(run)
                                    } label: {
                                        Label("Force Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }

                if orchestrator.activeRunners.isEmpty && activeRuns.isEmpty {
                    Section {
                        ContentUnavailableView("No Active Agents", systemImage: "bolt.slash", description: Text("Run an agent from a task to see it here."))
                    }
                }

                if !completedRuns.isEmpty {
                    Section("History") {
                        let displayedRuns = Array(completedRuns.prefix(historyLimit))
                        ForEach(displayedRuns, id: \.id) { run in
                            AgentRunRow(run: run, isActive: false)
                                .tag(run.id)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        if selectedRunId == run.id {
                                            selectedRunId = nil
                                        }
                                        orchestrator.deleteRun(run)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        .onDelete { indexSet in
                            let runsToDelete = indexSet.map { displayedRuns[$0] }
                            for run in runsToDelete {
                                if selectedRunId == run.id {
                                    selectedRunId = nil
                                }
                            }
                            orchestrator.deleteRuns(runsToDelete)
                        }

                        if completedRuns.count > historyLimit {
                            Button {
                                historyLimit += 10
                            } label: {
                                Text("Load More...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 250, ideal: 280)
            .toolbar {
                ToolbarItem {
                    Button(action: { orchestrator.cancelAll() }) {
                        Label("Cancel All", systemImage: "stop.circle")
                    }
                    .disabled(orchestrator.activeRunners.isEmpty)
                }
            }
        } detail: {
            if let runId = selectedRunId,
               let run = activeRuns.first(where: { $0.id == runId })
                   ?? completedRuns.first(where: { $0.id == runId }) {
                AgentSessionView(run: run, project: project)
            } else {
                ContentUnavailableView("Select a Session", systemImage: "bolt.circle", description: Text("Select an agent session to view details."))
            }
        }
        .navigationTitle("\(project.name) — Activity")
        .confirmationDialog(
            "Clear all history?",
            isPresented: $showClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                selectedRunId = nil
                let projectId = project.id
                let descriptor = FetchDescriptor<AgentRun>(
                    predicate: #Predicate { $0.projectId == projectId && $0.statusRaw != "running" && $0.statusRaw != "queued" },
                    sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
                )
                let allCompleted = (try? modelContext.fetch(descriptor)) ?? []
                orchestrator.deleteRuns(allCompleted)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all completed agent runs from history. Active runs will not be affected.")
        }
    }
}

struct AgentRunRow: View {
    let run: AgentRun
    let isActive: Bool

    var statusIcon: String {
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

    var statusColor: Color {
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

            VStack(alignment: .leading, spacing: 2) {
                Text(run.task?.title ?? run.taskTitle)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(run.relativeTimeFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let cost = run.costUSD {
                        Text(String(format: "$%.4f", cost))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(run.durationFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isActive {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
