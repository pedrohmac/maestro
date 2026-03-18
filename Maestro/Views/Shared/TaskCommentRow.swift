import SwiftUI
import MaestroCore

struct TaskCommentRow: View {
    let comment: TaskComment
    var onNavigateToRun: ((String) -> Void)? = nil
    @State private var isHoveringViewRun = false

    var body: some View {
        if comment.authorType == .narration {
            narrationRow
        } else {
            standardRow
        }
    }

    // MARK: - Narration Row

    private var narrationRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.bubble.fill")
                .foregroundStyle(.teal)
                .font(.caption2)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Progress")
                        .font(.caption2.bold())
                        .foregroundStyle(.teal)
                    Text(comment.createdDate.relativeFormatted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let run = comment.agentRun, let onNavigateToRun {
                        Spacer()
                        Button {
                            onNavigateToRun(run.id)
                        } label: {
                            Label("View Run", systemImage: "arrow.right.circle")
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.teal.opacity(isHoveringViewRun ? 0.22 : 0.12), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.teal.opacity(isHoveringViewRun ? 0.5 : 0.25), lineWidth: 1))
                                .shadow(color: Color.teal.opacity(isHoveringViewRun ? 0.3 : 0), radius: 4)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.teal)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isHoveringViewRun = hovering
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(comment.body.components(separatedBy: "\n"), id: \.self) { line in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.teal.opacity(0.5))
                                .frame(width: 4, height: 4)
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.teal.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.teal.opacity(0.12), lineWidth: 0.5)
        )
    }

    // MARK: - Standard Row (User / Agent)

    private var standardRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: comment.authorType == .agent ? "bolt.fill" : "person.fill")
                .foregroundStyle(comment.authorType == .agent ? .orange : .blue)
                .font(.caption)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.authorType.rawValue)
                        .font(.caption.bold())
                    Text(comment.createdDate.relativeFormatted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let run = comment.agentRun, let onNavigateToRun {
                        Spacer()
                        Button {
                            onNavigateToRun(run.id)
                        } label: {
                            Label("View Run", systemImage: "arrow.right.circle")
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(isHoveringViewRun ? 0.22 : 0.12), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.orange.opacity(isHoveringViewRun ? 0.5 : 0.25), lineWidth: 1))
                                .shadow(color: Color.orange.opacity(isHoveringViewRun ? 0.3 : 0), radius: 4)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isHoveringViewRun = hovering
                            }
                        }
                    }
                }

                Text(comment.body)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (comment.authorType == .agent ? Color.orange : Color.blue).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }
}
