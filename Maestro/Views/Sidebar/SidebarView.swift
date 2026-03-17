import SwiftUI
import SwiftData
import MaestroCore

struct SidebarView: View {
    let projects: [Project]
    @Binding var selectedProject: Project?
    @Binding var selectedNav: NavigationItem?
    @Binding var showingNewProject: Bool
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List(selection: $selectedProject) {
            Section("Views") {
                navRow("Kanban Board", systemImage: "rectangle.split.3x1", item: .kanban, shortcut: "1")
                navRow("Agent Activity", systemImage: "bolt.circle", item: .activity, shortcut: "2")
                navRow("Gantt Chart", systemImage: "chart.bar.xaxis", item: .gantt, shortcut: "3")
                navRow("Project Settings", systemImage: "gearshape", item: .settings, shortcut: "4")
            }

            Section("Projects") {
                ForEach(projects, id: \.id) { project in
                    HStack {
                        Label(project.name, systemImage: "folder.fill")
                        Spacer()
                        Text("\(project.tasks?.count ?? 0)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    .tag(project)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            if selectedProject?.id == project.id {
                                selectedProject = nil
                            }
                            modelContext.delete(project)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .tint(.gray)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        .toolbar {
            ToolbarItem {
                Button(action: { showingNewProject = true }) {
                    Label("New Project", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private func navRow(_ title: String, systemImage: String, item: NavigationItem, shortcut: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text("⌘\(shortcut)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selectedNav == item ? Color.gray.opacity(0.25) : Color.clear)
        )
        .foregroundStyle(selectedNav == item ? .primary : .secondary)
        .onTapGesture { selectedNav = item }
    }
}
