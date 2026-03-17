import Foundation
import MaestroCore

struct WorkspaceManager {
    static func resolveWorkspace(task: ProjectTask, project: Project) throws -> String {
        let root = project.workspaceRoot
        guard !root.isEmpty else {
            throw WorkspaceError.noWorkspaceRoot
        }

        let rootURL = URL(fileURLWithPath: root)
        guard FileManager.default.fileExists(atPath: root) else {
            throw WorkspaceError.workspaceNotFound(root)
        }

        switch project.workspaceStrategy {
        case .shared:
            if !project.defaultBranch.isEmpty {
                checkoutBranch(project.defaultBranch, in: root)
            }
            return root

        case .isolated:
            let isolatedPath = rootURL
                .appendingPathComponent(".maestro-workspaces")
                .appendingPathComponent(task.id)

            let path = isolatedPath.path
            if !FileManager.default.fileExists(atPath: path) {
                try createIsolatedWorkspace(source: root, destination: path)
            }
            return path
        }
    }

    private static func checkoutBranch(_ branch: String, in directory: String) {
        let gitDir = URL(fileURLWithPath: directory).appendingPathComponent(".git").path
        guard FileManager.default.fileExists(atPath: gitDir) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["checkout", branch]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try? process.run()
        process.waitUntilExit()
    }

    private static func createIsolatedWorkspace(source: String, destination: String) throws {
        let fm = FileManager.default
        let parentDir = URL(fileURLWithPath: destination).deletingLastPathComponent().path

        if !fm.fileExists(atPath: parentDir) {
            try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        }

        // Check if source is a git repo and use worktree
        let gitDir = URL(fileURLWithPath: source).appendingPathComponent(".git").path
        if fm.fileExists(atPath: gitDir) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["worktree", "add", destination, "--detach"]
            process.currentDirectoryURL = URL(fileURLWithPath: source)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                // Fallback: just create the directory
                try fm.createDirectory(atPath: destination, withIntermediateDirectories: true)
            }
        } else {
            try fm.createDirectory(atPath: destination, withIntermediateDirectories: true)
        }
    }

    static func cleanup(task: ProjectTask, project: Project) {
        guard project.workspaceStrategy == .isolated else { return }

        let path = URL(fileURLWithPath: project.workspaceRoot)
            .appendingPathComponent(".maestro-workspaces")
            .appendingPathComponent(task.id)
            .path

        guard FileManager.default.fileExists(atPath: path) else { return }

        // Remove git worktree first
        let gitDir = URL(fileURLWithPath: project.workspaceRoot).appendingPathComponent(".git").path
        if FileManager.default.fileExists(atPath: gitDir) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["worktree", "remove", path, "--force"]
            process.currentDirectoryURL = URL(fileURLWithPath: project.workspaceRoot)
            try? process.run()
            process.waitUntilExit()
        }

        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Per-Task Worktree Lifecycle

    /// Creates a git worktree for a specific task with a dedicated branch.
    /// Called when a task with `useWorktree=true` moves to inProgress.
    static func createTaskWorktree(task: ProjectTask, project: Project) throws -> String {
        let root = project.workspaceRoot
        guard !root.isEmpty else {
            throw WorkspaceError.noWorkspaceRoot
        }
        guard FileManager.default.fileExists(atPath: root) else {
            throw WorkspaceError.workspaceNotFound(root)
        }

        let worktreePath = URL(fileURLWithPath: root)
            .appendingPathComponent(".maestro-workspaces")
            .appendingPathComponent(task.id)
            .path

        // If worktree already exists, just return the path
        if FileManager.default.fileExists(atPath: worktreePath) {
            return worktreePath
        }

        let parentDir = URL(fileURLWithPath: worktreePath).deletingLastPathComponent().path
        if !FileManager.default.fileExists(atPath: parentDir) {
            try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        }

        let branchName = taskBranchName(for: task)
        let baseBranch = project.defaultBranch.isEmpty ? "HEAD" : project.defaultBranch

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["worktree", "add", worktreePath, "-b", branchName, baseBranch]
        process.currentDirectoryURL = URL(fileURLWithPath: root)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            // If branch already exists, try adding worktree with existing branch
            let retryProcess = Process()
            retryProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            retryProcess.arguments = ["worktree", "add", worktreePath, branchName]
            retryProcess.currentDirectoryURL = URL(fileURLWithPath: root)
            retryProcess.standardOutput = Pipe()
            retryProcess.standardError = Pipe()

            try retryProcess.run()
            retryProcess.waitUntilExit()

            if retryProcess.terminationStatus != 0 {
                throw WorkspaceError.worktreeCreationFailed(worktreePath)
            }
        }

        return worktreePath
    }

    /// Merges the task's worktree branch into the project's default branch.
    /// Returns `.success` if merge succeeded, `.conflict` if there were conflicts.
    static func mergeTaskWorktree(task: ProjectTask, project: Project) -> MergeResult {
        let root = project.workspaceRoot
        guard !root.isEmpty, FileManager.default.fileExists(atPath: root) else {
            return .error("Workspace root not found")
        }

        let defaultBranch = project.defaultBranch.isEmpty ? "main" : project.defaultBranch
        let branchName = taskBranchName(for: task)

        // Checkout the default branch in the main workspace
        let checkoutProcess = Process()
        checkoutProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        checkoutProcess.arguments = ["checkout", defaultBranch]
        checkoutProcess.currentDirectoryURL = URL(fileURLWithPath: root)
        checkoutProcess.standardOutput = Pipe()
        checkoutProcess.standardError = Pipe()

        do {
            try checkoutProcess.run()
            checkoutProcess.waitUntilExit()
        } catch {
            return .error("Failed to checkout \(defaultBranch): \(error.localizedDescription)")
        }

        if checkoutProcess.terminationStatus != 0 {
            return .error("Failed to checkout \(defaultBranch)")
        }

        // Attempt merge
        let mergeProcess = Process()
        mergeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        mergeProcess.arguments = ["merge", branchName, "--no-ff", "-m", "Merge \(branchName) (Maestro task: \(task.title))"]
        mergeProcess.currentDirectoryURL = URL(fileURLWithPath: root)

        let mergePipe = Pipe()
        mergeProcess.standardOutput = mergePipe
        mergeProcess.standardError = mergePipe

        do {
            try mergeProcess.run()
            mergeProcess.waitUntilExit()
        } catch {
            return .error("Failed to run merge: \(error.localizedDescription)")
        }

        if mergeProcess.terminationStatus != 0 {
            // Merge conflict — abort the merge
            let abortProcess = Process()
            abortProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            abortProcess.arguments = ["merge", "--abort"]
            abortProcess.currentDirectoryURL = URL(fileURLWithPath: root)
            abortProcess.standardOutput = Pipe()
            abortProcess.standardError = Pipe()
            try? abortProcess.run()
            abortProcess.waitUntilExit()

            return .conflict
        }

        // Merge succeeded — clean up worktree and branch
        cleanupTaskWorktree(task: task, project: project)

        return .success
    }

    /// Removes the task's worktree and optionally its branch.
    static func cleanupTaskWorktree(task: ProjectTask, project: Project) {
        let root = project.workspaceRoot
        guard let worktreePath = task.worktreePath,
              FileManager.default.fileExists(atPath: worktreePath) else { return }

        let gitDir = URL(fileURLWithPath: root).appendingPathComponent(".git").path
        guard FileManager.default.fileExists(atPath: gitDir) else { return }

        // Remove the worktree
        let removeProcess = Process()
        removeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        removeProcess.arguments = ["worktree", "remove", worktreePath, "--force"]
        removeProcess.currentDirectoryURL = URL(fileURLWithPath: root)
        removeProcess.standardOutput = Pipe()
        removeProcess.standardError = Pipe()
        try? removeProcess.run()
        removeProcess.waitUntilExit()

        // Delete the branch
        let branchName = taskBranchName(for: task)
        let deleteBranchProcess = Process()
        deleteBranchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        deleteBranchProcess.arguments = ["branch", "-d", branchName]
        deleteBranchProcess.currentDirectoryURL = URL(fileURLWithPath: root)
        deleteBranchProcess.standardOutput = Pipe()
        deleteBranchProcess.standardError = Pipe()
        try? deleteBranchProcess.run()
        deleteBranchProcess.waitUntilExit()

        try? FileManager.default.removeItem(atPath: worktreePath)
    }

    /// Returns the branch name used for a task's worktree.
    static func taskBranchName(for task: ProjectTask) -> String {
        return "maestro/task-\(task.id)"
    }

    // MARK: - Git SHA Helpers

    /// Returns the current HEAD SHA in the given directory, or nil if not a git repo.
    static func gitHeadSha(in directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "HEAD"]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Commits all changes in the working tree if any exist. Returns true if a commit was made.
    @discardableResult
    static func gitAutoCommit(message: String, in directory: String) -> Bool {
        print("[WorkspaceManager] gitAutoCommit called in: \(directory)")

        // Check if there are any changes to commit
        let statusProcess = Process()
        statusProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        statusProcess.arguments = ["status", "--porcelain"]
        statusProcess.currentDirectoryURL = URL(fileURLWithPath: directory)

        let statusPipe = Pipe()
        statusProcess.standardOutput = statusPipe
        let statusErrPipe = Pipe()
        statusProcess.standardError = statusErrPipe

        do {
            try statusProcess.run()
            statusProcess.waitUntilExit()
            guard statusProcess.terminationStatus == 0 else {
                let errData = statusErrPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                print("[WorkspaceManager] git status failed (\(statusProcess.terminationStatus)): \(errStr)")
                return false
            }
            let data = statusPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !output.isEmpty else {
                print("[WorkspaceManager] No uncommitted changes to auto-commit")
                return false
            }
            print("[WorkspaceManager] Found changes to commit:\n\(output)")
        } catch {
            print("[WorkspaceManager] git status error: \(error.localizedDescription)")
            return false
        }

        // Stage all changes
        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        addProcess.arguments = ["add", "-A"]
        addProcess.currentDirectoryURL = URL(fileURLWithPath: directory)
        addProcess.standardOutput = Pipe()
        let addErrPipe = Pipe()
        addProcess.standardError = addErrPipe

        do {
            try addProcess.run()
            addProcess.waitUntilExit()
            guard addProcess.terminationStatus == 0 else {
                let errData = addErrPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                print("[WorkspaceManager] git add failed (\(addProcess.terminationStatus)): \(errStr)")
                return false
            }
        } catch {
            print("[WorkspaceManager] git add error: \(error.localizedDescription)")
            return false
        }

        // Commit
        let commitProcess = Process()
        commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess.arguments = ["commit", "-m", message]
        commitProcess.currentDirectoryURL = URL(fileURLWithPath: directory)
        let commitOutPipe = Pipe()
        commitProcess.standardOutput = commitOutPipe
        let commitErrPipe = Pipe()
        commitProcess.standardError = commitErrPipe

        do {
            try commitProcess.run()
            commitProcess.waitUntilExit()
            if commitProcess.terminationStatus == 0 {
                print("[WorkspaceManager] Auto-commit succeeded")
                return true
            } else {
                let errData = commitErrPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                print("[WorkspaceManager] git commit failed (\(commitProcess.terminationStatus)): \(errStr)")
                return false
            }
        } catch {
            print("[WorkspaceManager] git commit error: \(error.localizedDescription)")
            return false
        }
    }

    /// Returns commits between two SHAs (exclusive of fromSha, inclusive of toSha).
    /// Each commit is returned as (sha, message, authorName, authorDate).
    static func gitLogBetween(from fromSha: String, to toSha: String, in directory: String) -> [(sha: String, message: String, authorName: String, authorDate: Date)] {
        guard fromSha != toSha else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // Use a delimiter to parse fields reliably
        process.arguments = ["log", "\(fromSha)..\(toSha)", "--format=%H%n%s%n%an%n%aI", "--reverse"]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else { return [] }

            let lines = output.components(separatedBy: "\n")
            var commits: [(sha: String, message: String, authorName: String, authorDate: Date)] = []
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime]

            // Each commit is 4 lines: sha, message, authorName, authorDate
            var i = 0
            while i + 3 < lines.count {
                let sha = lines[i]
                let message = lines[i + 1]
                let authorName = lines[i + 2]
                let dateStr = lines[i + 3]
                let authorDate = dateFormatter.date(from: dateStr) ?? Date()
                commits.append((sha: sha, message: message, authorName: authorName, authorDate: authorDate))
                i += 4
            }
            return commits
        } catch {
            return []
        }
    }

    /// Resets the git repo at the given directory to the specified commit SHA.
    /// Returns nil on success, or an error message on failure.
    static func gitResetHard(to sha: String, in directory: String) -> String? {
        guard FileManager.default.fileExists(atPath: directory) else {
            return "Directory not found: \(directory)"
        }

        // Also clean untracked files the agent may have created
        let resetProcess = Process()
        resetProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        resetProcess.arguments = ["reset", "--hard", sha]
        resetProcess.currentDirectoryURL = URL(fileURLWithPath: directory)

        let pipe = Pipe()
        resetProcess.standardOutput = pipe
        resetProcess.standardError = pipe

        do {
            try resetProcess.run()
            resetProcess.waitUntilExit()
            if resetProcess.terminationStatus != 0 {
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
                return "git reset failed: \(output)"
            }
        } catch {
            return "Failed to run git reset: \(error.localizedDescription)"
        }

        // Clean untracked files created during the run
        let cleanProcess = Process()
        cleanProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        cleanProcess.arguments = ["clean", "-fd"]
        cleanProcess.currentDirectoryURL = URL(fileURLWithPath: directory)
        cleanProcess.standardOutput = Pipe()
        cleanProcess.standardError = Pipe()
        try? cleanProcess.run()
        cleanProcess.waitUntilExit()

        return nil
    }
}

enum MergeResult {
    case success
    case conflict
    case error(String)
}

enum WorkspaceError: LocalizedError {
    case noWorkspaceRoot
    case workspaceNotFound(String)
    case worktreeCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWorkspaceRoot:
            return "No workspace root configured for this project."
        case .workspaceNotFound(let path):
            return "Workspace directory not found: \(path)"
        case .worktreeCreationFailed(let path):
            return "Failed to create worktree at: \(path)"
        }
    }
}
