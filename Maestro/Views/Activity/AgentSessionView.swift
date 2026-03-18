import SwiftUI
import SwiftData
import MaestroCore

struct AgentSessionView: View {
    let run: AgentRun
    let project: Project
    @Environment(AgentOrchestrator.self) private var orchestrator
    @Environment(\.isDarkerMode) private var isDarkerMode
    @State private var followUpText = ""
    @State private var autoScroll = true
    @State private var showRollbackConfirmation = false
    @State private var rollbackError: String?
    @State private var showRollbackError = false

    private var runner: AgentRunner? {
        guard let taskId = run.task?.id else { return nil }
        return orchestrator.getRunner(for: taskId)
    }

    private var isActive: Bool {
        runner?.isRunning ?? false
    }

    private var savedEvents: [AgentEvent] {
        guard let data = run.eventsData else { return [] }
        return (try? JSONDecoder().decode([AgentEvent].self, from: data)) ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.task?.title ?? "Agent Session")
                        .font(.headline)
                    HStack(spacing: 12) {
                        Label(run.status.rawValue, systemImage: isActive ? "bolt.fill" : "circle")
                            .font(.caption)
                            .foregroundStyle(isActive ? .orange : .secondary)
                        Text(run.durationFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let tokens = run.tokensUsed {
                            Text("\(tokens) tokens")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let cost = run.costUSD {
                            Text(String(format: "$%.4f", cost))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if isActive {
                    Button(action: {
                        if let taskId = run.task?.id {
                            orchestrator.cancelAgent(taskId: taskId)
                        }
                    }) {
                        Label("Cancel", systemImage: "stop.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    if run.canRollback {
                        Button {
                            showRollbackConfirmation = true
                        } label: {
                            Label("Rollback", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                    }
                    if let sessionId = run.sessionId, let task = run.task {
                        Button(action: {
                            orchestrator.resumeAgent(task: task, project: project, sessionId: sessionId)
                        }) {
                            Label("Resume", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()

            Divider()

            // Output area - chat-like
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if let runner = runner {
                            groupedEventsView(for: runner.events)
                        } else if !savedEvents.isEmpty {
                            groupedEventsView(for: savedEvents)
                        } else {
                            Text(run.log.isEmpty ? "No output recorded" : run.log)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()

                    // Scroll anchor
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .onChange(of: runner?.events.count ?? savedEvents.count) { _, _ in
                    if autoScroll {
                        withAnimation {
                            proxy.scrollTo("bottom")
                        }
                    }
                }
            }
            .background(Color.textBackground(darker: isDarkerMode))

            Divider()

            // Input area for follow-up messages
            if isActive {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Send a follow-up message...", text: $followUpText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                        .onKeyPress(.return, phases: .down) { keyPress in
                            if keyPress.modifiers.contains(EventModifiers.shift) {
                                return .ignored
                            }
                            sendFollowUp()
                            return .handled
                        }

                    Button(action: sendFollowUp) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(followUpText.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding()
            }
        }
        .confirmationDialog(
            "Rollback this agent run?",
            isPresented: $showRollbackConfirmation,
            titleVisibility: .visible
        ) {
            Button("Rollback", role: .destructive) {
                if let error = orchestrator.rollbackRun(run) {
                    rollbackError = error
                    showRollbackError = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset the workspace to the Git state before the agent ran. This action cannot be undone.")
        }
        .alert("Rollback Failed", isPresented: $showRollbackError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rollbackError ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func groupedEventsView(for events: [AgentEvent]) -> some View {
        ForEach(groupEvents(events)) { item in
            switch item {
            case .important(let indexed):
                AgentEventBubble(
                    event: indexed.event,
                    permissionResolution: resolutionForEvent(indexed.event)
                )
                .id(indexed.id)
            case .noiseGroup(let noiseEvents):
                NoiseGroupBubble(events: noiseEvents)
                    .id(noiseEvents[0].id)
            }
        }
    }

    private func resolutionForEvent(_ event: AgentEvent) -> PermissionResolution? {
        guard case .permissionRequest(_, _, let requestId) = event else { return nil }
        return runner?.pendingPermissions.first(where: { $0.id == requestId })?.resolution
    }

    private func sendFollowUp() {
        guard !followUpText.isEmpty, let taskId = run.task?.id else { return }
        orchestrator.sendMessage(to: taskId, message: followUpText)
        followUpText = ""
    }
}

// MARK: - Event Grouping

private struct IndexedEvent: Identifiable {
    let id: Int
    let event: AgentEvent
}

private enum EventDisplayItem: Identifiable {
    case important(IndexedEvent)
    case noiseGroup([IndexedEvent])

    var id: Int {
        switch self {
        case .important(let item): return item.id
        case .noiseGroup(let events): return events[0].id
        }
    }
}

private func isNoiseEvent(_ event: AgentEvent) -> Bool {
    switch event {
    case .assistantText: return false
    case .toolUse(let name, _): return name != "Edit"
    case .toolResult: return true
    case .result: return false
    case .error: return false
    case .toolError: return false
    case .systemMessage: return true
    case .permissionRequest: return false
    case .userMessage: return false
    }
}

private func groupEvents(_ events: [AgentEvent]) -> [EventDisplayItem] {
    var items: [EventDisplayItem] = []
    var noiseBuffer: [IndexedEvent] = []

    for (index, event) in events.enumerated() {
        if isNoiseEvent(event) {
            noiseBuffer.append(IndexedEvent(id: index, event: event))
        } else {
            if !noiseBuffer.isEmpty {
                items.append(.noiseGroup(noiseBuffer))
                noiseBuffer = []
            }
            items.append(.important(IndexedEvent(id: index, event: event)))
        }
    }

    if !noiseBuffer.isEmpty {
        items.append(.noiseGroup(noiseBuffer))
    }

    return items
}

struct AgentEventBubble: View {
    let event: AgentEvent
    var permissionResolution: PermissionResolution?
    @Environment(\.isDarkerMode) private var isDarkerMode
    @State private var isToolUseExpanded = true
    @State private var isToolResultExpanded = true

    var body: some View {
        bubbleContent
            .copyable(event.copyableText)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch event {
        case .assistantText(let text):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "brain")
                    .foregroundStyle(.purple)
                    .font(.caption)
                    .padding(.top, 3)
                Text(text)
                    .font(.system(.body, design: .default))
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

        case .toolUse(let name, let input):
            if name == "Edit", let editInfo = EditToolInfo.parse(from: input) {
                EditToolBubble(editInfo: editInfo, isExpanded: $isToolUseExpanded)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "wrench.fill").foregroundStyle(.blue).font(.caption)
                        Text(name).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        Spacer()
                        Image(systemName: isToolUseExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isToolUseExpanded.toggle() } }

                    if isToolUseExpanded {
                        Text(input)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                }
                .padding(8)
                .background(Color.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }

        case .toolResult(let name, let output):
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").foregroundStyle(.green).font(.caption)
                    Text("\(name) result")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isToolResultExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isToolResultExpanded.toggle() } }

                if isToolResultExpanded {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(output.prefix(2000))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                    .padding(6)
                }
            }
            .padding(8)
            .background(Color.green.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

        case .result(let sessionId, let costUSD, let tokensUsed, _):
            HStack(spacing: 12) {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session Complete")
                        .font(.caption.bold())
                    HStack(spacing: 8) {
                        if let sid = sessionId {
                            Text("ID: \(sid.prefix(12))...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let cost = costUSD {
                            Text(String(format: "$%.4f", cost))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let tokens = tokensUsed {
                            Text("\(tokens) tokens")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

        case .error(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text(message)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

        case .toolError(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(message)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

        case .systemMessage(let message):
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(6)

        case .permissionRequest(let toolName, let input, _):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text("Permission Request")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(toolName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if !input.isEmpty {
                    Text(input)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.controlBackground(darker: isDarkerMode), in: RoundedRectangle(cornerRadius: 4))
                }

                if let resolution = permissionResolution {
                    switch resolution {
                    case .allowed(let auto):
                        Label(auto ? "Auto-allowed by rule" : "Allowed from sidebar", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .denied(let auto):
                        Label(auto ? "Auto-denied by rule" : "Denied from sidebar", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    case .pending:
                        Label("Awaiting approval in task sidebar...", systemImage: "clock.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

        case .userMessage(let text):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                    .padding(.top, 3)
                Text(text)
                    .font(.system(.body, design: .default))
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Noise Group Display

private struct NoiseGroupBubble: View {
    let events: [IndexedEvent]
    @State private var isExpanded = false

    private var toolNames: [String] {
        var names: [String] = []
        for item in events {
            if case .toolUse(let name, _) = item.event, !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.2")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("\(events.count) tool \(events.count == 1 ? "step" : "steps")")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !toolNames.isEmpty {
                    Text("· \(toolNames.joined(separator: ", "))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(events) { item in
                        AgentEventBubble(event: item.event)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Edit Tool Pretty Display

struct EditToolInfo {
    let filePath: String
    let oldString: String
    let newString: String
    let replaceAll: Bool

    static func parse(from input: String) -> EditToolInfo? {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let filePath = json["file_path"] as? String,
              let oldString = json["old_string"] as? String,
              let newString = json["new_string"] as? String else {
            return nil
        }
        let replaceAll = json["replace_all"] as? Bool ?? false
        return EditToolInfo(filePath: filePath, oldString: oldString, newString: newString, replaceAll: replaceAll)
    }

    var fileName: String {
        (filePath as NSString).lastPathComponent
    }
}

struct EditToolBubble: View {
    let editInfo: EditToolInfo
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "pencil.line")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Edit")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text(editInfo.fileName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                if editInfo.replaceAll {
                    Text("(all)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    // File path
                    Text(editInfo.filePath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 6)
                        .padding(.bottom, 8)

                    // Removed lines
                    DiffBlock(text: editInfo.oldString, isRemoval: true)

                    // Added lines
                    DiffBlock(text: editInfo.newString, isRemoval: false)
                        .padding(.top, 2)
                }
                .padding(6)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DiffBlock: View {
    let text: String
    let isRemoval: Bool

    var body: some View {
        let prefix = isRemoval ? "−" : "+"
        let color: Color = isRemoval ? .red : .green
        let bgColor: Color = isRemoval ? .red.opacity(0.08) : .green.opacity(0.08)

        HStack(alignment: .top, spacing: 0) {
            // Gutter
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, _ in
                    Text(prefix)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(color.opacity(0.6))
                        .frame(height: 16)
                }
            }
            .padding(.trailing, 4)
            .padding(.leading, 4)

            // Content
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(color)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 16)
                }
            }
            .padding(.leading, 4)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bgColor, in: RoundedRectangle(cornerRadius: 4))
    }

    private var lines: [String] {
        text.components(separatedBy: "\n")
    }
}

// MARK: - Copy to Clipboard

private extension AgentEvent {
    var copyableText: String {
        switch self {
        case .assistantText(let text):
            return text
        case .toolUse(let name, let input):
            if name == "Edit", let editInfo = EditToolInfo.parse(from: input) {
                var text = "Edit: \(editInfo.filePath)"
                if editInfo.replaceAll { text += " (replace all)" }
                text += "\n"
                for line in editInfo.oldString.components(separatedBy: "\n") {
                    text += "- \(line)\n"
                }
                for line in editInfo.newString.components(separatedBy: "\n") {
                    text += "+ \(line)\n"
                }
                return text
            }
            return "\(name):\n\(input)"
        case .toolResult(_, let output):
            return output
        case .result(let sessionId, let costUSD, let tokensUsed, let durationMs):
            var parts: [String] = ["Session Complete"]
            if let sid = sessionId { parts.append("ID: \(sid)") }
            if let cost = costUSD { parts.append(String(format: "Cost: $%.4f", cost)) }
            if let tokens = tokensUsed { parts.append("Tokens: \(tokens)") }
            if let duration = durationMs { parts.append("Duration: \(duration)ms") }
            return parts.joined(separator: "\n")
        case .error(let message):
            return message
        case .toolError(let message):
            return message
        case .systemMessage(let message):
            return message
        case .permissionRequest(let toolName, let input, _):
            return "Permission Request: \(toolName)\n\(input)"
        case .userMessage(let text):
            return "User: \(text)"
        }
    }
}

private struct CopyableOverlay: ViewModifier {
    let text: String
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if isHovered {
                    CopyButton(text: text)
                        .padding(.top, 4)
                        .padding(.trailing, 4)
                        .transition(.opacity)
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

private struct CopyButton: View {
    let text: String
    @State private var showCopied = false

    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            showCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopied = false
            }
        }) {
            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                .font(.caption2)
                .foregroundStyle(showCopied ? .green : .secondary)
                .padding(4)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}

extension View {
    fileprivate func copyable(_ text: String) -> some View {
        modifier(CopyableOverlay(text: text))
    }
}
