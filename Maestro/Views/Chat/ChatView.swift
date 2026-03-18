import SwiftUI
import MaestroCore

struct ChatView: View {
    let project: Project
    @Environment(AgentOrchestrator.self) private var orchestrator
    @Environment(\.isDarkerMode) private var isDarkerMode
    @State private var messageText = ""
    @State private var autoScroll = true

    private var runner: AgentRunner? {
        orchestrator.getChatRunner(for: project.id)
    }

    private var isActive: Bool {
        runner?.isRunning ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat")
                        .font(.headline)
                    Text(project.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isActive {
                    Button(action: {
                        orchestrator.endChat(projectId: project.id)
                    }) {
                        Label("End Chat", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else if runner != nil {
                    // Session ended but runner hasn't been cleaned up yet
                    Button(action: {
                        orchestrator.endChat(projectId: project.id)
                    }) {
                        Label("New Chat", systemImage: "plus.bubble")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()

            Divider()

            // Messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if let runner = runner {
                            chatEventsView(for: runner.events)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.text.bubble.right")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.tertiary)
                                Text("Ask anything about this project")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                Text("Questions about the codebase, how to test, implementation details, etc.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        }
                    }
                    .padding()

                    Color.clear
                        .frame(height: 1)
                        .id("chatBottom")
                }
                .onChange(of: runner?.events.count ?? 0) { _, _ in
                    if autoScroll {
                        withAnimation {
                            proxy.scrollTo("chatBottom")
                        }
                    }
                }
            }
            .background(Color.textBackground(darker: isDarkerMode))

            Divider()

            // Input area - always visible
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask a question...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onKeyPress(.return, phases: .down) { keyPress in
                        if keyPress.modifiers.contains(EventModifiers.shift) {
                            return .ignored
                        }
                        sendMessage()
                        return .handled
                    }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func chatEventsView(for events: [AgentEvent]) -> some View {
        ForEach(chatGroupEvents(events)) { item in
            switch item {
            case .userMsg(let indexed):
                chatUserBubble(indexed.event)
                    .id(indexed.id)
            case .assistantMsg(let indexed):
                chatAssistantBubble(indexed.event)
                    .id(indexed.id)
            case .workingGroup(let items):
                ChatWorkingGroupBubble(events: items)
                    .id(items[0].id)
            case .other(let indexed):
                AgentEventBubble(event: indexed.event)
                    .id(indexed.id)
            }
        }
    }

    @ViewBuilder
    private func chatUserBubble(_ event: AgentEvent) -> some View {
        if case .userMessage(let text) = event {
            HStack {
                Spacer(minLength: 60)
                Text(text)
                    .font(.system(.body, design: .default))
                    .textSelection(.enabled)
                    .padding(10)
                    .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    @ViewBuilder
    private func chatAssistantBubble(_ event: AgentEvent) -> some View {
        if case .assistantText(let text) = event {
            HStack {
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
                .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                Spacer(minLength: 60)
            }
        }
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let runner = runner, isActive {
            // Send follow-up to active session (process still running)
            orchestrator.sendChatMessage(projectId: project.id, message: text)
        } else if let runner = runner, runner.sessionId != nil {
            // Process exited but we have a session ID — resume the conversation
            orchestrator.resumeChat(project: project, message: text)
        } else {
            // No runner or no session ID — start a new chat session
            orchestrator.endChat(projectId: project.id) // Clean up any dead runner
            orchestrator.startChat(project: project, initialMessage: text)
        }

        messageText = ""
    }
}

// MARK: - Chat Event Grouping

private struct ChatIndexedEvent: Identifiable {
    let id: Int
    let event: AgentEvent
}

private enum ChatDisplayItem: Identifiable {
    case userMsg(ChatIndexedEvent)
    case assistantMsg(ChatIndexedEvent)
    case workingGroup([ChatIndexedEvent])
    case other(ChatIndexedEvent)

    var id: Int {
        switch self {
        case .userMsg(let item): return item.id
        case .assistantMsg(let item): return item.id
        case .workingGroup(let items): return items[0].id
        case .other(let item): return item.id
        }
    }
}

private func chatGroupEvents(_ events: [AgentEvent]) -> [ChatDisplayItem] {
    var items: [ChatDisplayItem] = []
    var workingBuffer: [ChatIndexedEvent] = []

    for (index, event) in events.enumerated() {
        let indexed = ChatIndexedEvent(id: index, event: event)

        switch event {
        case .userMessage:
            if !workingBuffer.isEmpty {
                items.append(.workingGroup(workingBuffer))
                workingBuffer = []
            }
            items.append(.userMsg(indexed))

        case .assistantText:
            if !workingBuffer.isEmpty {
                items.append(.workingGroup(workingBuffer))
                workingBuffer = []
            }
            items.append(.assistantMsg(indexed))

        case .error, .toolError:
            if !workingBuffer.isEmpty {
                items.append(.workingGroup(workingBuffer))
                workingBuffer = []
            }
            items.append(.other(indexed))

        case .result:
            if !workingBuffer.isEmpty {
                items.append(.workingGroup(workingBuffer))
                workingBuffer = []
            }
            items.append(.other(indexed))

        default:
            // Tool use, tool result, system messages, permissions -> working group
            workingBuffer.append(indexed)
        }
    }

    if !workingBuffer.isEmpty {
        items.append(.workingGroup(workingBuffer))
    }

    return items
}

// MARK: - Working Group Bubble

private struct ChatWorkingGroupBubble: View {
    let events: [ChatIndexedEvent]
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

    private var summary: String {
        let count = events.filter { if case .toolUse = $0.event { return true } else { return false } }.count
        if count == 0 { return "\(events.count) steps" }
        return "\(count) tool \(count == 1 ? "call" : "calls")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.2")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(summary)
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
