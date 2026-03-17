import SwiftUI
import SwiftData
import MaestroCore
import Charts

struct GanttChartView: View {
    @Bindable var project: Project
    @State private var selectedTask: ProjectTask?

    var tasks: [ProjectTask] {
        (project.tasks ?? []).sorted { ($0.startDate ?? $0.createdDate) < ($1.startDate ?? $1.createdDate) }
    }

    func barColor(for status: TaskStatus) -> Color {
        switch status {
        case .todo: return .blue
        case .inProgress: return .orange
        case .review: return .purple
        case .done: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            if tasks.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "chart.bar.xaxis", description: Text("Create tasks to see them on the Gantt chart."))
            } else {
                ScrollView {
                    Chart(tasks, id: \.id) { task in
                        let start = task.startDate ?? task.createdDate
                        let end = task.dueDate ?? task.completedDate ?? Calendar.current.date(byAdding: .day, value: 3, to: start)!

                        BarMark(
                            xStart: .value("Start", start),
                            xEnd: .value("End", end),
                            y: .value("Task", task.title)
                        )
                        .foregroundStyle(barColor(for: task.status))
                        .cornerRadius(4)
                        .annotation(position: .overlay, alignment: .leading) {
                            Text(task.title)
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.leading, 4)
                        }

                        // Today marker
                        RuleMark(x: .value("Today", Date()))
                            .foregroundStyle(.red.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                        }
                    }
                    .frame(height: max(CGFloat(tasks.count) * 44, 200))
                    .padding()
                }

                // Legend
                HStack(spacing: 16) {
                    ForEach(TaskStatus.allCases) { status in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(barColor(for: status))
                                .frame(width: 8, height: 8)
                            Text(status.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(.red.opacity(0.5))
                            .frame(width: 16, height: 1)
                        Text("Today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("\(project.name) — Gantt")
    }
}
