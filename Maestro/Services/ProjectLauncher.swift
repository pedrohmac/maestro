import Foundation
import AppKit
import MaestroCore

enum LaunchStepStatus: Equatable {
    case pending
    case running
    case completed
    case failed(String)
}

@MainActor
@Observable
final class ProjectLauncher {
    var isLaunching = false
    var stepStatuses: [String: LaunchStepStatus] = [:]
    var currentConfig: LaunchConfig?
    var launchError: String?
    var launchedProjectId: String?

    private var backgroundProcesses: [Process] = []
    private var launchTask: Task<Void, Never>?

    var isGeneratingConfig = false
    var generationError: String?
    private var generationProcess: Process?
    private var generationTask: Task<Void, Never>?

    // MARK: - Launch

    func launch(project: Project) {
        guard !isLaunching else { return }
        guard !project.workspaceRoot.isEmpty else {
            launchError = "No workspace root set"
            return
        }

        guard let config = LaunchConfig.load(from: project.workspaceRoot) else {
            launchError = "No launch configuration found. Configure it in Project Settings or generate one with Claude."
            return
        }

        guard !config.steps.isEmpty else {
            launchError = "Launch configuration has no steps"
            return
        }

        isLaunching = true
        currentConfig = config
        launchError = nil
        launchedProjectId = project.id
        stepStatuses = [:]
        for step in config.steps {
            stepStatuses[step.id] = .pending
        }

        launchTask = Task {
            await executeLaunch(config: config, workspaceRoot: project.workspaceRoot)
        }
    }

    func stop() {
        launchTask?.cancel()
        for process in backgroundProcesses where process.isRunning {
            process.terminate()
        }
        backgroundProcesses.removeAll()
        isLaunching = false
        launchedProjectId = nil
    }

    // MARK: - Config Generation

    func generateConfig(workspaceRoot: String, claudePath: String) {
        guard !isGeneratingConfig else { return }

        isGeneratingConfig = true
        generationError = nil

        generationTask = Task {
            let resolvedPath = await ClaudePathResolver.resolve(preferredPath: claudePath)

            let prompt = """
            Analyze this project and generate a launch configuration JSON that describes how to run this project locally for testing/development. Output ONLY valid JSON with no preamble, explanation, or markdown fences.

            The JSON format must be:
            {
              "steps": [
                {
                  "id": "unique-id",
                  "name": "Human-readable step name",
                  "command": "shell command to run",
                  "workingDirectory": null,
                  "background": false,
                  "waitSeconds": null
                }
              ],
              "openUrl": "http://localhost:3000",
              "readyCheckUrl": "http://localhost:3000",
              "readyCheckTimeoutSeconds": 30
            }

            Rules:
            - Steps with "background": true are for long-running processes (servers, watchers). They run in the background.
            - Steps with "background": false run sequentially and must complete before the next step.
            - "waitSeconds" is optional delay after starting a background step (give it time to boot).
            - "workingDirectory" is relative to the project root (null means project root).
            - "openUrl" is the URL to open in the browser when everything is ready.
            - "readyCheckUrl" is polled until it responds before opening the browser.
            - Include dependency installation steps (npm install, pip install, etc.) as foreground steps.
            - Include database/service startup if needed (docker compose, etc.).
            - Include the main dev server as a background step.
            - Be practical — only include steps that are actually needed for THIS project.
            """

            let proc = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            let shellCmd = [resolvedPath, "-p", prompt, "--output-format", "text", "--max-turns", "5", "--allowedTools", "Bash,Read,Glob,Grep"]
                .map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
                .joined(separator: " ")

            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-l", "-c", shellCmd]
            proc.currentDirectoryURL = URL(fileURLWithPath: workspaceRoot)
            proc.standardOutput = stdoutPipe
            proc.standardError = stderrPipe
            proc.environment = [
                "HOME": NSHomeDirectory(),
                "USER": NSUserName(),
                "SHELL": "/bin/zsh",
                "TERM": "xterm-256color",
                "LANG": "en_US.UTF-8",
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "TMPDIR": NSTemporaryDirectory(),
                "NO_COLOR": "1"
            ]

            generationProcess = proc

            do {
                try proc.run()
            } catch {
                generationError = "Failed to start Claude: \(error.localizedDescription)"
                isGeneratingConfig = false
                generationProcess = nil
                return
            }

            let (output, errorOutput, exitStatus) = await withCheckedContinuation { (continuation: CheckedContinuation<(String, String, Int32), Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()
                    let output = String(data: stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let errOutput = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: (output, errOutput, proc.terminationStatus))
                }
            }

            generationProcess = nil

            guard !Task.isCancelled else {
                isGeneratingConfig = false
                return
            }

            if exitStatus != 0 {
                let suffix = errorOutput.isEmpty ? "" : ": \(String(errorOutput.suffix(200)))"
                generationError = "Claude exited with code \(exitStatus)\(suffix)"
                isGeneratingConfig = false
                return
            }

            // Extract JSON from output (may have surrounding text)
            var jsonString = output
            if let startRange = output.range(of: "{"),
               let endRange = output.range(of: "}", options: .backwards),
               startRange.lowerBound <= endRange.upperBound {
                jsonString = String(output[startRange.lowerBound...endRange.upperBound])
            }

            guard let jsonData = jsonString.data(using: .utf8),
                  let config = try? JSONDecoder().decode(LaunchConfig.self, from: jsonData) else {
                generationError = "Claude output was not valid launch config JSON"
                isGeneratingConfig = false
                return
            }

            // Save to file
            do {
                try config.save(to: workspaceRoot)
                generationError = nil
            } catch {
                generationError = "Generated config but failed to save: \(error.localizedDescription)"
            }

            isGeneratingConfig = false
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationProcess?.terminate()
        isGeneratingConfig = false
    }

    // MARK: - Private

    private func executeLaunch(config: LaunchConfig, workspaceRoot: String) async {
        for step in config.steps {
            guard !Task.isCancelled else { break }

            stepStatuses[step.id] = .running

            let directory: String
            if let wd = step.workingDirectory, !wd.isEmpty {
                directory = "\(workspaceRoot)/\(wd)"
            } else {
                directory = workspaceRoot
            }

            if step.background {
                let error = launchBackground(command: step.command, directory: directory)
                if let error {
                    stepStatuses[step.id] = .failed(error)
                } else {
                    stepStatuses[step.id] = .completed
                }

                if let wait = step.waitSeconds, wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                }
            } else {
                let error = await runForeground(command: step.command, directory: directory)
                if let error {
                    stepStatuses[step.id] = .failed(error)
                    launchError = "Step '\(step.name)' failed: \(error)"
                    isLaunching = false
                    return
                }
                stepStatuses[step.id] = .completed
            }
        }

        // Open URL when ready
        if let urlString = config.openUrl {
            if let checkUrl = config.readyCheckUrl {
                let timeout = config.readyCheckTimeoutSeconds ?? 30
                await waitForReady(url: checkUrl, timeoutSeconds: timeout)
            }
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }

        // Stay in launching state if background processes are running
        if backgroundProcesses.allSatisfy({ !$0.isRunning }) {
            isLaunching = false
            launchedProjectId = nil
        }
    }

    private func launchBackground(command: String, directory: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", command]
        proc.currentDirectoryURL = URL(fileURLWithPath: directory)
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.environment = [
            "HOME": NSHomeDirectory(),
            "USER": NSUserName(),
            "SHELL": "/bin/zsh",
            "TERM": "xterm-256color",
            "LANG": "en_US.UTF-8",
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": NSTemporaryDirectory()
        ]

        do {
            try proc.run()
            backgroundProcesses.append(proc)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func runForeground(command: String, directory: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                let stderrPipe = Pipe()
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                proc.arguments = ["-l", "-c", command]
                proc.currentDirectoryURL = URL(fileURLWithPath: directory)
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = stderrPipe
                proc.environment = [
                    "HOME": NSHomeDirectory(),
                    "USER": NSUserName(),
                    "SHELL": "/bin/zsh",
                    "TERM": "xterm-256color",
                    "LANG": "en_US.UTF-8",
                    "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                    "TMPDIR": NSTemporaryDirectory()
                ]

                do {
                    try proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus != 0 {
                        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let msg = String(data: stderrData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                        continuation.resume(returning: "Exit code \(proc.terminationStatus): \(String(msg.prefix(200)))")
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(returning: error.localizedDescription)
                }
            }
        }
    }

    private func waitForReady(url: String, timeoutSeconds: Int) async {
        guard let checkUrl = URL(string: url) else { return }
        let start = Date()
        while Date().timeIntervalSince(start) < Double(timeoutSeconds) {
            if Task.isCancelled { return }
            if await checkReachable(checkUrl) { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func checkReachable(_ url: URL) async -> Bool {
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse {
                return (200...399).contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }
}
