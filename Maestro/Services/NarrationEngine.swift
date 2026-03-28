import Foundation
import MaestroCore

/// Translates raw agent events into plain-English progress narration.
/// Only tool use events produce narration — assistant text and tool results are skipped
/// since they represent reasoning and output, not user-visible actions.
struct NarrationEngine {

    /// Returns a human-readable narration string for an event, or nil if it shouldn't be narrated.
    static func narrate(event: AgentEvent) -> String? {
        switch event {
        case .toolUse(let name, let input):
            return narrateToolUse(name: name, input: input)
        case .error(let message):
            if ConnectionChecker.isConnectionError(message) {
                return "Connection issue: The AI API appears unreachable. Check your internet connection and try again."
            }
            let truncated = message.prefix(120)
            return "Encountered an error: \(truncated)"
        default:
            return nil
        }
    }

    // MARK: - Tool Narration

    private static func narrateToolUse(name: String, input: String) -> String? {
        let fields = parseInputFields(input)

        switch name {
        case "Write":
            let file = filename(from: fields["file_path"] ?? fields["path"] ?? "")
            return file.isEmpty ? "Creating a new file" : "Creating \(file)"

        case "Edit":
            let file = filename(from: fields["file_path"] ?? fields["path"] ?? "")
            return file.isEmpty ? "Editing code" : "Editing \(file)"

        case "Read":
            let file = filename(from: fields["file_path"] ?? fields["path"] ?? "")
            return file.isEmpty ? "Reading files" : "Reading \(file)"

        case "Bash":
            let command = fields["command"] ?? ""
            return narrateBash(command)

        case "Grep":
            let pattern = fields["pattern"] ?? fields["query"] ?? ""
            return pattern.isEmpty
                ? "Searching the codebase"
                : "Searching for \"\(pattern.prefix(50))\""

        case "Glob":
            let pattern = fields["pattern"] ?? ""
            return pattern.isEmpty
                ? "Looking for files"
                : "Looking for \(pattern) files"

        case "Agent":
            let desc = fields["description"] ?? ""
            return desc.isEmpty
                ? "Launching a sub-agent"
                : "Launching sub-agent: \(desc.prefix(60))"

        case "TodoWrite":
            return "Updating task progress"

        case "WebFetch", "web_fetch":
            return "Fetching web content"

        case "WebSearch", "web_search":
            let query = fields["query"] ?? ""
            return query.isEmpty
                ? "Searching the web"
                : "Searching the web for \"\(query.prefix(50))\""

        case "NotebookEdit":
            return "Editing notebook"

        case "LSP":
            return "Analyzing code structure"

        default:
            return nil
        }
    }

    private static func narrateBash(_ command: String) -> String? {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return "Running a command" }

        // Test runners
        if cmd.contains("test") || cmd.contains("jest") || cmd.contains("pytest")
            || cmd.contains("xcodebuild test") || cmd.contains("vitest")
            || cmd.contains("rspec") || cmd.contains("cargo test") {
            return "Running tests"
        }
        // Package install
        if cmd.contains("npm install") || cmd.contains("yarn add")
            || cmd.contains("pip install") || cmd.contains("brew install")
            || cmd.contains("pnpm install") || cmd.contains("cargo add") {
            return "Installing dependencies"
        }
        // Build
        if cmd.contains("npm run build") || cmd.contains("xcodebuild")
            || cmd.contains("cargo build") || cmd.contains("make")
            || cmd.contains("swift build") || cmd.contains("gradle build") {
            return "Building the project"
        }
        // Git
        if cmd.contains("git commit") { return "Committing changes" }
        if cmd.contains("git push") { return "Pushing to remote" }
        if cmd.contains("git checkout") || cmd.contains("git switch") { return "Switching branches" }
        if cmd.contains("git status") || cmd.contains("git diff") || cmd.contains("git log") {
            return "Checking git history"
        }
        if cmd.contains("git stash") { return "Stashing changes" }
        if cmd.contains("git merge") { return "Merging branches" }
        if cmd.contains("git rebase") { return "Rebasing branch" }
        // Lint / format
        if cmd.contains("lint") || cmd.contains("eslint") || cmd.contains("swiftlint") {
            return "Linting code"
        }
        if cmd.contains("format") || cmd.contains("prettier") || cmd.contains("swift-format") {
            return "Formatting code"
        }
        // Directory ops
        if cmd.hasPrefix("mkdir") { return "Creating directory" }
        if cmd.hasPrefix("rm ") { return "Removing files" }
        if cmd.hasPrefix("cd ") { return "Navigating to directory" }
        // Script runners
        if cmd.contains("npm run") || cmd.contains("yarn run") || cmd.contains("npx") {
            return "Running project script"
        }

        // Fallback: show the first word of the command
        let firstWord = cmd.components(separatedBy: .whitespaces).first ?? "command"
        return "Running \(firstWord)"
    }

    // MARK: - Helpers

    private static func parseInputFields(_ input: String) -> [String: String] {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: String] = [:]
        for (key, value) in json {
            if let str = value as? String {
                result[key] = str
            }
        }
        return result
    }

    private static func filename(from path: String) -> String {
        guard !path.isEmpty else { return "" }
        return (path as NSString).lastPathComponent
    }
}
