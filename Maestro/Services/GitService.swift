import Foundation

struct GitBranchInfo {
    let name: String
    let isCurrent: Bool
    let taskId: String?     // Extracted from maestro/task-<id>
    let aheadCount: Int
    let behindCount: Int
    let isPushed: Bool       // Has a remote tracking branch
    let hasConflict: Bool    // Would conflict if merged into base
    let lastCommitDate: Date?
    let lastCommitMessage: String?
}

struct GitDiffFile {
    let path: String
    let status: String    // "M", "A", "D", "R"
    let additions: Int
    let deletions: Int
}

struct GitGraphCommit: Identifiable {
    let id: String       // full SHA
    let shortSha: String
    let message: String
    let authorName: String
    let authorDate: Date
    let parents: [String]
    let refs: [GitRef]
}

struct GitRef {
    let name: String
    let isHead: Bool
    let isRemote: Bool
    let isTag: Bool
}

struct GitService {
    // MARK: - Branch Operations

    /// Lists all maestro/* branches in the repo.
    static func listMaestroBranches(in directory: String, baseBranch: String) -> [GitBranchInfo] {
        let branchNames = listAllBranches(in: directory).filter { $0.hasPrefix("maestro/") }
        return branchNames.compactMap { branchName in
            branchInfo(branch: branchName, baseBranch: baseBranch, in: directory)
        }
    }

    /// Returns all local branch names.
    static func listAllBranches(in directory: String) -> [String] {
        let output = runGit(["branch", "--format=%(refname:short)"], in: directory)
        guard let output, !output.isEmpty else { return [] }
        return output.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    /// Builds a GitBranchInfo for a specific branch.
    static func branchInfo(branch: String, baseBranch: String, in directory: String) -> GitBranchInfo? {
        // Check if branch exists
        guard runGit(["rev-parse", "--verify", branch], in: directory) != nil else { return nil }

        let current = currentBranch(in: directory)
        let isCurrent = current == branch

        // Extract task ID from maestro/task-<id>
        let taskId: String? = {
            let prefix = "maestro/task-"
            if branch.hasPrefix(prefix) {
                return String(branch.dropFirst(prefix.count))
            }
            return nil
        }()

        // Ahead/behind count relative to base
        let (ahead, behind) = aheadBehind(branch: branch, base: baseBranch, in: directory)

        // Check if pushed to remote
        let isPushed = hasRemoteTrackingBranch(branch, in: directory)

        // Conflict detection
        let hasConflict = wouldConflict(branch: branch, into: baseBranch, in: directory)

        // Last commit info
        let lastCommitOutput = runGit(["log", "-1", "--format=%aI%n%s", branch], in: directory)
        var lastDate: Date?
        var lastMessage: String?
        if let lines = lastCommitOutput?.components(separatedBy: "\n"), lines.count >= 2 {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            lastDate = formatter.date(from: lines[0])
            lastMessage = lines[1]
        }

        return GitBranchInfo(
            name: branch,
            isCurrent: isCurrent,
            taskId: taskId,
            aheadCount: ahead,
            behindCount: behind,
            isPushed: isPushed,
            hasConflict: hasConflict,
            lastCommitDate: lastDate,
            lastCommitMessage: lastMessage
        )
    }

    /// Returns the current branch name.
    static func currentBranch(in directory: String) -> String? {
        runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: directory)
    }

    // MARK: - Commit Operations

    /// Returns commits on `branch` that are not on `baseBranch`.
    static func branchCommits(branch: String, baseBranch: String, in directory: String) -> [(sha: String, shortSha: String, message: String, authorName: String, authorDate: Date)] {
        let range = "\(baseBranch)..\(branch)"
        let output = runGit(["log", range, "--format=%H%n%h%n%s%n%an%n%aI", "--reverse"], in: directory)
        guard let output, !output.isEmpty else { return [] }

        let lines = output.components(separatedBy: "\n")
        var commits: [(sha: String, shortSha: String, message: String, authorName: String, authorDate: Date)] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var i = 0
        while i + 4 < lines.count {
            let sha = lines[i]
            let shortSha = lines[i + 1]
            let message = lines[i + 2]
            let authorName = lines[i + 3]
            let dateStr = lines[i + 4]
            let authorDate = formatter.date(from: dateStr) ?? Date()
            commits.append((sha: sha, shortSha: shortSha, message: message, authorName: authorName, authorDate: authorDate))
            i += 5
        }
        return commits
    }

    // MARK: - Graph Operations

    /// Returns all commits for graph visualization, in topological order (newest first).
    static func allCommitsForGraph(in directory: String, maxCount: Int = 200) -> [GitGraphCommit] {
        let sep = "\u{1e}" // ASCII Record Separator
        let format = "%H\(sep)%P\(sep)%s\(sep)%an\(sep)%aI\(sep)%D"
        let output = runGit(["log", "--all", "--topo-order", "--format=\(format)", "-\(maxCount)"], in: directory)
        guard let output, !output.isEmpty else { return [] }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        return output.components(separatedBy: "\n").compactMap { line in
            let fields = line.components(separatedBy: sep)
            guard fields.count >= 5 else { return nil }

            let sha = fields[0]
            guard !sha.isEmpty else { return nil }
            let parentLine = fields[1]
            let message = fields[2]
            let author = fields[3]
            let dateStr = fields[4]
            let refsLine = fields.count > 5 ? fields[5] : ""

            let parents = parentLine.isEmpty ? [] : parentLine.components(separatedBy: " ")
            let date = formatter.date(from: dateStr) ?? Date()
            let refs = parseRefs(refsLine)

            return GitGraphCommit(
                id: sha,
                shortSha: String(sha.prefix(7)),
                message: message,
                authorName: author,
                authorDate: date,
                parents: parents,
                refs: refs
            )
        }
    }

    private static func parseRefs(_ refString: String) -> [GitRef] {
        guard !refString.isEmpty else { return [] }
        return refString.components(separatedBy: ", ").compactMap { part in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            if trimmed.hasPrefix("HEAD -> ") {
                let name = String(trimmed.dropFirst("HEAD -> ".count))
                return GitRef(name: name, isHead: true, isRemote: false, isTag: false)
            } else if trimmed == "HEAD" {
                return GitRef(name: "HEAD", isHead: true, isRemote: false, isTag: false)
            } else if trimmed.hasPrefix("tag: ") {
                let name = String(trimmed.dropFirst("tag: ".count))
                return GitRef(name: name, isHead: false, isRemote: false, isTag: true)
            } else if trimmed.contains("/") {
                return GitRef(name: trimmed, isHead: false, isRemote: true, isTag: false)
            } else {
                return GitRef(name: trimmed, isHead: false, isRemote: false, isTag: false)
            }
        }
    }

    // MARK: - Diff Operations

    /// Returns list of changed files between branch and base.
    static func diffFiles(branch: String, baseBranch: String, in directory: String) -> [GitDiffFile] {
        let output = runGit(["diff", "--numstat", "\(baseBranch)...\(branch)"], in: directory)
        guard let output, !output.isEmpty else { return [] }

        let statusOutput = runGit(["diff", "--name-status", "\(baseBranch)...\(branch)"], in: directory)
        let statusLines = statusOutput?.components(separatedBy: "\n").filter { !$0.isEmpty } ?? []
        var statusMap: [String: String] = [:]
        for line in statusLines {
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 2 {
                statusMap[parts.last ?? ""] = String(parts[0].prefix(1))
            }
        }

        return output.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3 else { return nil }
            let adds = Int(parts[0]) ?? 0
            let dels = Int(parts[1]) ?? 0
            let path = parts[2]
            let status = statusMap[path] ?? "M"
            return GitDiffFile(path: path, status: status, additions: adds, deletions: dels)
        }
    }

    /// Returns the full diff for a specific file between branch and base.
    static func fileDiff(branch: String, baseBranch: String, file: String, in directory: String) -> String? {
        runGit(["diff", "\(baseBranch)...\(branch)", "--", file], in: directory)
    }

    /// Returns the full diff between branch and base.
    static func fullDiff(branch: String, baseBranch: String, in directory: String) -> String? {
        runGit(["diff", "\(baseBranch)...\(branch)"], in: directory)
    }

    // MARK: - Push Operations

    /// Pushes a branch to the remote.
    static func push(branch: String, in directory: String) -> (success: Bool, message: String) {
        let result = runGitWithStatus(["push", "-u", "origin", branch], in: directory)
        return result
    }

    // MARK: - PR Operations

    /// Creates a pull request using the `gh` CLI. Returns (success, prURL or error message).
    static func createPR(branch: String, title: String, body: String, baseBranch: String, in directory: String) -> (success: Bool, message: String) {
        // First ensure the branch is pushed
        let pushResult = push(branch: branch, in: directory)
        if !pushResult.success {
            return (false, "Failed to push branch: \(pushResult.message)")
        }

        let ghPath = findGhPath()
        guard let ghPath else {
            return (false, "GitHub CLI (gh) not found. Install it with: brew install gh")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = ["pr", "create", "--base", baseBranch, "--head", branch, "--title", title, "--body", body]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                let url = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return (true, url)
            } else {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                return (false, errStr)
            }
        } catch {
            return (false, "Failed to run gh: \(error.localizedDescription)")
        }
    }

    // MARK: - Merge / Rebase

    /// Merges branch into baseBranch. Returns (success, message).
    static func merge(branch: String, into baseBranch: String, in directory: String) -> (success: Bool, message: String) {
        // Checkout base branch
        let checkoutResult = runGitWithStatus(["checkout", baseBranch], in: directory)
        guard checkoutResult.success else {
            return (false, "Failed to checkout \(baseBranch): \(checkoutResult.message)")
        }

        let mergeResult = runGitWithStatus(["merge", branch, "--no-ff", "-m", "Merge \(branch)"], in: directory)
        if !mergeResult.success {
            // Abort the merge
            _ = runGitWithStatus(["merge", "--abort"], in: directory)
            return (false, "Merge conflict or error: \(mergeResult.message)")
        }

        return (true, "Successfully merged \(branch) into \(baseBranch)")
    }

    /// Rebases branch onto baseBranch. Returns (success, message).
    static func rebase(branch: String, onto baseBranch: String, in directory: String) -> (success: Bool, message: String) {
        // Checkout the feature branch
        let checkoutResult = runGitWithStatus(["checkout", branch], in: directory)
        guard checkoutResult.success else {
            return (false, "Failed to checkout \(branch): \(checkoutResult.message)")
        }

        let rebaseResult = runGitWithStatus(["rebase", baseBranch], in: directory)
        if !rebaseResult.success {
            _ = runGitWithStatus(["rebase", "--abort"], in: directory)
            return (false, "Rebase conflict or error: \(rebaseResult.message)")
        }

        return (true, "Successfully rebased \(branch) onto \(baseBranch)")
    }

    // MARK: - Helpers

    /// Returns (ahead, behind) count of branch relative to base.
    static func aheadBehind(branch: String, base: String, in directory: String) -> (ahead: Int, behind: Int) {
        let output = runGit(["rev-list", "--left-right", "--count", "\(base)...\(branch)"], in: directory)
        guard let output else { return (0, 0) }
        let parts = output.components(separatedBy: "\t")
        guard parts.count >= 2 else { return (0, 0) }
        let behind = Int(parts[0].trimmingCharacters(in: .whitespaces)) ?? 0
        let ahead = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
        return (ahead, behind)
    }

    /// Checks if a branch has a remote tracking branch.
    static func hasRemoteTrackingBranch(_ branch: String, in directory: String) -> Bool {
        let output = runGit(["branch", "-r", "--list", "origin/\(branch)"], in: directory)
        return output != nil && !output!.isEmpty
    }

    /// Checks if merging `branch` into `target` would produce conflicts.
    static func wouldConflict(branch: String, into target: String, in directory: String) -> Bool {
        // Use merge-tree to check for conflicts without modifying the worktree
        let mergeBase = runGit(["merge-base", target, branch], in: directory)
        guard let base = mergeBase else { return false }

        let result = runGitExitCode(["merge-tree", base, target, branch], in: directory)
        // merge-tree outputs conflict markers if there are conflicts
        // A non-zero exit code or output containing "<<<" indicates conflicts
        if let output = result.output, output.contains("<" + "<<<<<") {
            return true
        }
        return false
    }

    /// Checks whether a remote named "origin" exists.
    static func hasRemote(in directory: String) -> Bool {
        let output = runGit(["remote"], in: directory)
        guard let output else { return false }
        return output.components(separatedBy: "\n").contains("origin")
    }

    /// Finds the `gh` CLI binary path.
    private static func findGhPath() -> String? {
        let candidates = ["/usr/local/bin/gh", "/opt/homebrew/bin/gh", "/usr/bin/gh"]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        // Try which
        let output = runShell(["which", "gh"])
        if let output, !output.isEmpty {
            return output
        }
        return nil
    }

    // MARK: - Process Helpers

    static func runGit(_ arguments: [String], in directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
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

    static func runGitWithStatus(_ arguments: [String], in directory: String) -> (success: Bool, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let outStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus == 0 {
                return (true, outStr.isEmpty ? errStr : outStr)
            } else {
                return (false, errStr.isEmpty ? outStr : errStr)
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private static func runGitExitCode(_ arguments: [String], in directory: String) -> (exitCode: Int32, output: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)
            return (process.terminationStatus, output)
        } catch {
            return (-1, nil)
        }
    }

    private static func runShell(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments

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
}
