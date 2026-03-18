import SwiftUI
import MaestroCore

// MARK: - Layout Types

struct GraphRow {
    let commit: GitGraphCommit
    let lane: Int
    let colorIndex: Int
    let incoming: [GraphEdge]   // segments in top half of the row
    let outgoing: [GraphEdge]   // segments in bottom half of the row
}

struct GraphEdge {
    let fromLane: Int
    let toLane: Int
    let colorIndex: Int
}

// MARK: - Layout Engine

enum GitGraphLayout {
    static let branchColors: [Color] = [
        Color(red: 0.35, green: 0.65, blue: 1.0),
        Color(red: 0.40, green: 0.82, blue: 0.45),
        Color(red: 1.00, green: 0.60, blue: 0.20),
        Color(red: 0.72, green: 0.45, blue: 0.95),
        Color(red: 1.00, green: 0.40, blue: 0.40),
        Color(red: 0.30, green: 0.82, blue: 0.82),
        Color(red: 0.92, green: 0.78, blue: 0.20),
        Color(red: 1.00, green: 0.50, blue: 0.70),
        Color(red: 0.40, green: 0.85, blue: 0.65),
        Color(red: 0.35, green: 0.60, blue: 0.75),
        Color(red: 0.55, green: 0.45, blue: 0.90),
        Color(red: 0.70, green: 0.55, blue: 0.40),
    ]

    static func color(at index: Int) -> Color {
        branchColors[index % branchColors.count]
    }

    /// Computes the graph layout for commits in topological order (newest first).
    static func compute(commits: [GitGraphCommit]) -> (rows: [GraphRow], maxLanes: Int) {
        var lanes: [String?] = []
        var laneColorIndices: [Int] = []
        var nextColor = 0
        var rows: [GraphRow] = []
        var globalMaxLanes = 0

        for commit in commits {
            // Find all lanes expecting this commit
            let matchingIndices = lanes.enumerated()
                .compactMap { $0.element == commit.id ? $0.offset : nil }

            let myLane: Int
            let myColor: Int

            if let firstMatch = matchingIndices.first {
                myLane = firstMatch
                myColor = laneColorIndices[firstMatch]
            } else {
                // New branch tip — find empty slot or extend
                if let emptyIdx = lanes.firstIndex(where: { $0 == nil }) {
                    myLane = emptyIdx
                } else {
                    myLane = lanes.count
                    lanes.append(nil)
                    laneColorIndices.append(0)
                }
                myColor = nextColor
                nextColor = (nextColor + 1) % branchColors.count
                lanes[myLane] = commit.id
                laneColorIndices[myLane] = myColor
            }

            // --- Incoming edges (top half) ---
            var incoming: [GraphEdge] = []
            for (i, sha) in lanes.enumerated() {
                guard sha != nil else { continue }
                if matchingIndices.contains(i) {
                    incoming.append(GraphEdge(
                        fromLane: i,
                        toLane: myLane,
                        colorIndex: i == myLane ? myColor : laneColorIndices[i]
                    ))
                } else {
                    incoming.append(GraphEdge(fromLane: i, toLane: i, colorIndex: laneColorIndices[i]))
                }
            }

            // Clear all matching lanes
            for idx in matchingIndices {
                lanes[idx] = nil
            }

            // --- Outgoing edges (bottom half) ---
            var outgoing: [GraphEdge] = []
            var handledOutLanes = Set<Int>()

            if commit.parents.isEmpty {
                // Root commit — lane ends
            } else {
                let firstParent = commit.parents[0]

                if let existingLane = lanes.firstIndex(of: firstParent) {
                    // First parent already tracked elsewhere — converge
                    outgoing.append(GraphEdge(fromLane: myLane, toLane: existingLane, colorIndex: myColor))
                    handledOutLanes.insert(existingLane)
                } else {
                    // First parent continues in same lane
                    lanes[myLane] = firstParent
                    laneColorIndices[myLane] = myColor
                    outgoing.append(GraphEdge(fromLane: myLane, toLane: myLane, colorIndex: myColor))
                    handledOutLanes.insert(myLane)
                }

                // Additional parents (merge)
                for i in 1..<commit.parents.count {
                    let parent = commit.parents[i]
                    if let existingLane = lanes.firstIndex(of: parent) {
                        outgoing.append(GraphEdge(
                            fromLane: myLane,
                            toLane: existingLane,
                            colorIndex: laneColorIndices[existingLane]
                        ))
                        handledOutLanes.insert(existingLane)
                    } else {
                        let newLane: Int
                        if let emptyIdx = lanes.firstIndex(where: { $0 == nil }) {
                            newLane = emptyIdx
                        } else {
                            newLane = lanes.count
                            lanes.append(nil)
                            laneColorIndices.append(0)
                        }
                        let pColor = nextColor
                        nextColor = (nextColor + 1) % branchColors.count
                        lanes[newLane] = parent
                        laneColorIndices[newLane] = pColor
                        outgoing.append(GraphEdge(fromLane: myLane, toLane: newLane, colorIndex: pColor))
                        handledOutLanes.insert(newLane)
                    }
                }
            }

            // Pass-through for other active lanes
            for (i, sha) in lanes.enumerated() {
                guard sha != nil, !handledOutLanes.contains(i) else { continue }
                outgoing.append(GraphEdge(fromLane: i, toLane: i, colorIndex: laneColorIndices[i]))
            }

            // Trim trailing nil lanes
            while !lanes.isEmpty && lanes.last == nil {
                lanes.removeLast()
                laneColorIndices.removeLast()
            }

            let rowMax = max(
                lanes.count,
                myLane + 1,
                (incoming.flatMap { [$0.fromLane, $0.toLane] }.max() ?? 0) + 1,
                (outgoing.flatMap { [$0.fromLane, $0.toLane] }.max() ?? 0) + 1
            )
            globalMaxLanes = max(globalMaxLanes, rowMax)

            rows.append(GraphRow(
                commit: commit,
                lane: myLane,
                colorIndex: myColor,
                incoming: incoming,
                outgoing: outgoing
            ))
        }

        return (rows, globalMaxLanes)
    }
}

// MARK: - Graph View

struct GitGraphView: View {
    let project: Project

    @Environment(\.isDarkerMode) private var isDarkerMode
    @State private var graphRows: [GraphRow] = []
    @State private var maxLanes = 1
    @State private var isLoading = false
    @State private var commitCount = 0
    @State private var maxCommits = 200
    @State private var selectedSha: String?
    @State private var hoveredSha: String?

    private let rowHeight: CGFloat = 34
    private let laneSpacing: CGFloat = 16
    private let lanePadding: CGFloat = 14
    private let nodeRadius: CGFloat = 4.0
    private let lineWidth: CGFloat = 2.0

    private var graphWidth: CGFloat {
        CGFloat(max(maxLanes, 1)) * laneSpacing + lanePadding * 2
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && graphRows.isEmpty {
                ProgressView("Loading commit graph...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if graphRows.isEmpty {
                ContentUnavailableView(
                    "No Commits",
                    systemImage: "point.3.filled.connected.trianglepath.dotted",
                    description: Text("No commits found in the repository.")
                )
            } else {
                graphContent
            }
        }
        .onAppear { loadGraph() }
        .onChange(of: project.id) { loadGraph() }
    }

    private var graphContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(graphRows.enumerated()), id: \.element.commit.id) { index, row in
                    GitGraphRowView(
                        row: row,
                        index: index,
                        graphWidth: graphWidth,
                        rowHeight: rowHeight,
                        laneSpacing: laneSpacing,
                        lanePadding: lanePadding,
                        nodeRadius: nodeRadius,
                        lineWidth: lineWidth,
                        isSelected: selectedSha == row.commit.id,
                        isHovered: hoveredSha == row.commit.id,
                        isDarkerMode: isDarkerMode
                    )
                    .onTapGesture {
                        selectedSha = selectedSha == row.commit.id ? nil : row.commit.id
                    }
                    .onHover { hovering in
                        hoveredSha = hovering ? row.commit.id : nil
                    }
                }

                if commitCount >= maxCommits {
                    Button {
                        maxCommits += 200
                        loadGraph()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "ellipsis.circle")
                            Text("Load more commits")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadGraph() {
        let root = project.workspaceRoot
        guard !root.isEmpty, FileManager.default.fileExists(atPath: root) else { return }

        isLoading = true
        let count = maxCommits

        Task.detached {
            let commits = GitService.allCommitsForGraph(in: root, maxCount: count)
            let (rows, maxL) = GitGraphLayout.compute(commits: commits)

            await MainActor.run {
                graphRows = rows
                maxLanes = maxL
                commitCount = commits.count
                isLoading = false
            }
        }
    }
}

// MARK: - Row View

private struct GitGraphRowView: View {
    let row: GraphRow
    let index: Int
    let graphWidth: CGFloat
    let rowHeight: CGFloat
    let laneSpacing: CGFloat
    let lanePadding: CGFloat
    let nodeRadius: CGFloat
    let lineWidth: CGFloat
    let isSelected: Bool
    let isHovered: Bool
    let isDarkerMode: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Graph rails
            Canvas { context, size in
                drawRails(context: context, size: size)
            }
            .frame(width: graphWidth, height: rowHeight)

            // Commit info
            commitInfoRow
        }
        .frame(height: rowHeight)
        .background(rowBackground)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            Color.accentColor.opacity(0.12)
        } else if isHovered {
            Color.primary.opacity(0.04)
        } else if index % 2 == 1 {
            Color.primary.opacity(0.015)
        } else {
            Color.clear
        }
    }

    private var commitInfoRow: some View {
        HStack(spacing: 8) {
            // SHA
            Text(row.commit.shortSha)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(GitGraphLayout.color(at: row.colorIndex))
                .textSelection(.enabled)

            // Ref badges (skip remote-only refs for a cleaner look)
            let localRefs = row.commit.refs.filter { !$0.isRemote }
            ForEach(Array(localRefs.enumerated()), id: \.offset) { _, ref in
                refBadge(ref)
            }

            // Message
            Text(row.commit.message)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            // Author
            Text(row.commit.authorName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Date
            Text(row.commit.authorDate.relativeFormatted)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.trailing, 12)
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func refBadge(_ ref: GitRef) -> some View {
        let (bgColor, fgColor): (Color, Color) = {
            if ref.isTag {
                return (.orange, .orange)
            } else if ref.isHead {
                return (.green, .green)
            } else {
                return (.blue, .blue)
            }
        }()

        HStack(spacing: 3) {
            if ref.isHead {
                Image(systemName: "arrowshape.right.fill")
                    .font(.system(size: 7))
            } else if ref.isTag {
                Image(systemName: "tag.fill")
                    .font(.system(size: 7))
            }
            Text(ref.name)
                .font(.system(.caption2, design: .monospaced))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(bgColor.opacity(0.15), in: Capsule())
        .foregroundStyle(fgColor)
    }

    // MARK: - Canvas Drawing

    private func drawRails(context: GraphicsContext, size: CGSize) {
        let mid = size.height / 2

        // Draw incoming edges (top half)
        for edge in row.incoming {
            drawEdge(context: context, edge: edge, fromY: 0, toY: mid, size: size)
        }

        // Draw outgoing edges (bottom half)
        for edge in row.outgoing {
            drawEdge(context: context, edge: edge, fromY: mid, toY: size.height, size: size)
        }

        // Draw commit node
        let nodeX = lanePadding + CGFloat(row.lane) * laneSpacing
        let nodeColor = GitGraphLayout.color(at: row.colorIndex)

        let isMergeOrRef = !row.commit.refs.isEmpty || row.commit.parents.count > 1

        if isMergeOrRef {
            // Larger node with outer ring for merge/ref commits
            let outerR = nodeRadius + 2
            let outerRect = CGRect(
                x: nodeX - outerR,
                y: mid - outerR,
                width: outerR * 2,
                height: outerR * 2
            )
            context.stroke(
                Path(ellipseIn: outerRect),
                with: .color(nodeColor),
                style: StrokeStyle(lineWidth: 1.5)
            )
        }

        // Inner filled circle
        let innerRect = CGRect(
            x: nodeX - nodeRadius,
            y: mid - nodeRadius,
            width: nodeRadius * 2,
            height: nodeRadius * 2
        )
        context.fill(Path(ellipseIn: innerRect), with: .color(nodeColor))
    }

    private func drawEdge(context: GraphicsContext, edge: GraphEdge, fromY: CGFloat, toY: CGFloat, size: CGSize) {
        let color = GitGraphLayout.color(at: edge.colorIndex)
        let fromX = lanePadding + CGFloat(edge.fromLane) * laneSpacing
        let toX = lanePadding + CGFloat(edge.toLane) * laneSpacing

        var path = Path()
        if abs(fromX - toX) < 0.5 {
            // Straight line
            path.move(to: CGPoint(x: fromX, y: fromY))
            path.addLine(to: CGPoint(x: toX, y: toY))
        } else {
            // Smooth S-curve
            let midY = (fromY + toY) / 2
            path.move(to: CGPoint(x: fromX, y: fromY))
            path.addCurve(
                to: CGPoint(x: toX, y: toY),
                control1: CGPoint(x: fromX, y: midY),
                control2: CGPoint(x: toX, y: midY)
            )
        }

        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }
}
