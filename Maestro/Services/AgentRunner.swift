import Foundation
import MaestroCore

enum PermissionResolution: Sendable {
    case pending
    case allowed(auto: Bool)  // auto=true means resolved by a rule
    case denied(auto: Bool)
}

struct PendingPermission: Identifiable, Sendable {
    let id: String          // = requestId
    let toolName: String
    let input: String
    let receivedAt: Date
    var resolution: PermissionResolution = .pending
}

@Observable
final class AgentRunner: Identifiable, @unchecked Sendable {
    let id: String
    let taskId: String
    let taskTitle: String

    private(set) var isRunning = false
    private(set) var wasCancelled = false
    private(set) var output: String = ""
    private(set) var events: [AgentEvent] = []
    private(set) var pendingPermissions: [PendingPermission] = []
    var sessionId: String?

    private var process: Process?
    private var stdinPipe: Pipe?
    private var continuation: AsyncStream<AgentEvent>.Continuation?
    private var timeoutTask: Task<Void, Never>?
    private var connectionErrorEmitted = false

    init(taskId: String, taskTitle: String) {
        self.id = UUID().uuidString
        self.taskId = taskId
        self.taskTitle = taskTitle
    }

    /// Stream of parsed events from the Claude process
    func eventStream() -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func addPendingPermission(requestId: String, toolName: String, input: String) {
        let permission = PendingPermission(
            id: requestId,
            toolName: toolName,
            input: input,
            receivedAt: Date()
        )
        pendingPermissions.append(permission)
    }

    func resolvePendingPermission(requestId: String, granted: Bool, auto: Bool) {
        if let index = pendingPermissions.firstIndex(where: { $0.id == requestId }) {
            pendingPermissions[index].resolution = granted
                ? .allowed(auto: auto)
                : .denied(auto: auto)
        }
        respondToPermission(requestId: requestId, granted: granted)
    }

    /// Start a new Claude session
    func start(
        prompt: String,
        workspacePath: String,
        allowedTools: String,
        maxTurns: Int,
        maxBudget: Double?,
        systemPrompt: String?,
        claudePath: String = "/usr/local/bin/claude",
        timeoutMinutes: Int = 30
    ) async {
        guard !isRunning else { return }

        let resolvedPath = await ClaudePathResolver.resolve(preferredPath: claudePath)

        var arguments = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose",
            "--include-partial-messages"
        ]

        if !allowedTools.isEmpty {
            arguments += ["--allowedTools", allowedTools]
        }

        if maxTurns > 0 {
            arguments += ["--max-turns", String(maxTurns)]
        }

        if let budget = maxBudget, budget > 0 {
            arguments += ["--max-cost", String(budget)]
        }

        if let sys = systemPrompt, !sys.isEmpty {
            arguments += ["--append-system-prompt", sys]
        }

        await runProcess(
            executablePath: resolvedPath,
            arguments: arguments,
            workspacePath: workspacePath,
            timeoutMinutes: timeoutMinutes
        )
    }

    /// Resume a previous Claude session
    func resume(
        sessionId: String,
        prompt: String?,
        workspacePath: String,
        claudePath: String = "/usr/local/bin/claude",
        timeoutMinutes: Int = 30
    ) async {
        guard !isRunning else { return }

        let resolvedPath = await ClaudePathResolver.resolve(preferredPath: claudePath)

        var arguments = [
            "--resume", sessionId,
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose",
            "--include-partial-messages"
        ]

        if let p = prompt, !p.isEmpty {
            arguments += ["-p", p]
        }

        await runProcess(
            executablePath: resolvedPath,
            arguments: arguments,
            workspacePath: workspacePath,
            timeoutMinutes: timeoutMinutes
        )
    }

    /// Add a user message to the visible events list (does not send to process)
    func addUserMessage(_ text: String) {
        events.append(.userMessage(text))
    }

    /// Send a follow-up message to the running process's stdin
    func sendMessage(_ text: String) {
        guard isRunning, let stdinPipe = stdinPipe else { return }

        // Record the user message as a visible event
        addUserMessage(text)

        // Format as JSON for stream-json input
        let message: [String: Any] = [
            "type": "user",
            "message": text
        ]

        if let data = try? JSONSerialization.data(withJSONObject: message),
           var jsonString = String(data: data, encoding: .utf8) {
            jsonString += "\n"
            if let messageData = jsonString.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(messageData)
            }
        }
    }

    /// Respond to a permission request from the Claude process
    func respondToPermission(requestId: String, granted: Bool) {
        guard isRunning, let stdinPipe = stdinPipe else { return }

        let response: [String: Any] = [
            "type": "permission_response",
            "permission_id": requestId,
            "result": granted ? "allow" : "deny"
        ]

        if let data = try? JSONSerialization.data(withJSONObject: response),
           var jsonString = String(data: data, encoding: .utf8) {
            jsonString += "\n"
            if let messageData = jsonString.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(messageData)
            }
        }
    }

    /// Cancel the running process
    func cancel() {
        timeoutTask?.cancel()
        process?.terminate()
        isRunning = false
        wasCancelled = true
        continuation?.yield(.systemMessage("Agent cancelled by user"))
        continuation?.finish()
    }

    // MARK: - Event Consolidation

    private func appendEvent(_ event: AgentEvent) {
        if case .assistantText(let newText) = event,
           let lastIndex = events.indices.last,
           case .assistantText(let existing) = events[lastIndex] {
            events[lastIndex] = .assistantText(existing + newText)
        } else {
            events.append(event)
        }
        continuation?.yield(event)
    }

    // MARK: - Private

    /// Single-quote escape a string for safe shell embedding
    private func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        workspacePath: String,
        timeoutMinutes: Int
    ) async {
        isRunning = true
        output = ""
        // Don't clear events — callers may have pre-populated user messages
        // (e.g. chat adds the initial message before start). Runners are always
        // freshly created so the array is empty unless intentionally seeded.
        pendingPermissions = []

        let proc = Process()
        let stdinP = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        // Launch through a login shell so claude gets the full user environment
        // (GUI apps inherit a minimal launchd environment missing shell profile vars)
        let shellCmd = ([executablePath] + arguments).map { shellEscape($0) }.joined(separator: " ")
        // Use `script` to give claude a full terminal session with controlling PTY.
        // The claude CLI (Bun runtime) requires a proper terminal to flush output.
        let fullShellCmd = "exec script -q /dev/null " + shellCmd
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", fullShellCmd]
        proc.currentDirectoryURL = URL(fileURLWithPath: workspacePath)
        proc.standardInput = stdinP
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        // Use a clean environment — Xcode injects debug variables that can
        // interfere with subprocess behavior. The login shell will source the
        // user's profile to add PATH extensions, API keys, etc.
        let env: [String: String] = [
            "HOME": NSHomeDirectory(),
            "USER": NSUserName(),
            "SHELL": "/bin/zsh",
            "TERM": "xterm-256color",
            "LANG": "en_US.UTF-8",
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": NSTemporaryDirectory(),
            "NO_COLOR": "1"
        ]
        proc.environment = env

        self.process = proc
        self.stdinPipe = stdinP

        // Set up timeout
        timeoutTask = Task {
            try? await Task.sleep(for: .seconds(timeoutMinutes * 60))
            if isRunning {
                continuation?.yield(.systemMessage("Agent timed out after \(timeoutMinutes) minutes"))
                cancel()
            }
        }

        do {
            try proc.run()
        } catch {
            print("[Runner] Failed to start process: \(error.localizedDescription)")
            isRunning = false
            let event = AgentEvent.error("Failed to start claude: \(error.localizedDescription)")
            appendEvent(event)
            continuation?.finish()
            return
        }

        // Close parent's copy of pipe write-ends so we get EOF when child exits
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        // Drain stderr on a background queue (captures shell-level errors before exec)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while true {
                let data = stderrHandle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    DispatchQueue.main.async {
                        // Always surface the raw stderr for debugging
                        let stderrEvent = AgentEvent.systemMessage("[stderr] \(text)")
                        self?.appendEvent(stderrEvent)

                        // Detect connection/API errors and emit a friendly warning (once)
                        if ConnectionChecker.isConnectionError(text),
                           !(self?.connectionErrorEmitted ?? true) {
                            self?.connectionErrorEmitted = true
                            self?.appendEvent(.error(ConnectionChecker.userMessage))
                        }
                    }
                }
            }
        }

        // Read stdout on a background queue, bridged back via CheckedContinuation
        await withCheckedContinuation { (outerCont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var buffer = Data()

                while true {
                    let newData = stdoutHandle.availableData
                    if newData.isEmpty {
                        // EOF — process any remaining buffer
                        let remainingLine: String?
                        let remainingEvent: AgentEvent?
                        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8)?
                            .replacingOccurrences(of: "\r", with: "")
                            .replacingOccurrences(of: "\\x1b\\[[0-9;]*[a-zA-Z]", with: "", options: .regularExpression) {
                            remainingLine = line
                            remainingEvent = OutputParser.parse(line: line)
                        } else {
                            remainingLine = nil
                            remainingEvent = nil
                        }

                        // Wait for process to fully exit so we can check its status
                        proc.waitUntilExit()
                        let exitCode = Int(proc.terminationStatus)

                        DispatchQueue.main.async {
                            if let line = remainingLine {
                                self?.output += line + "\n"
                                if let event = remainingEvent {
                                    self?.appendEvent(event)
                                }
                            }

                            // Emit error for non-zero exit when no error was already recorded
                            if exitCode != 0, let self = self {
                                let hasError = self.events.contains {
                                    if case .error = $0 { return true }
                                    return false
                                }
                                if !hasError {
                                    let errorMsg: String
                                    if ConnectionChecker.isConnectionError(self.output) {
                                        errorMsg = ConnectionChecker.userMessage
                                    } else {
                                        errorMsg = "Agent process exited unexpectedly (code \(exitCode))"
                                    }
                                    self.appendEvent(.error(errorMsg))
                                }
                            }

                            self?.isRunning = false
                            self?.timeoutTask?.cancel()
                            self?.continuation?.finish()
                            outerCont.resume()
                        }
                        return
                    }

                    buffer.append(newData)

                    // Split by newlines
                    var parsedLines: [(String, AgentEvent?)] = []
                    while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                        let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                        buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                        guard let line = String(data: lineData, encoding: .utf8)?
                            .replacingOccurrences(of: "\r", with: "")
                            .replacingOccurrences(of: "\\x1b\\[[0-9;]*[a-zA-Z]", with: "", options: .regularExpression)
                            else { continue }
                        parsedLines.append((line, OutputParser.parse(line: line)))
                    }

                    if !parsedLines.isEmpty {
                        DispatchQueue.main.async {
                            for (line, event) in parsedLines {
                                self?.output += line + "\n"
                                if let event = event {
                                    self?.appendEvent(event)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
