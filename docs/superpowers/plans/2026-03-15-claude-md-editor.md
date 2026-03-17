# CLAUDE.md Editor Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a CLAUDE.md editor to project settings with template/AI-generation options, and a setup prompt in the kanban board.

**Architecture:** File-based approach — reads/writes `{workspaceRoot}/CLAUDE.md` directly via FileManager. No model changes. Claude path resolution extracted to shared utility. Generation uses Foundation.Process with login shell wrapping (same as AgentRunner).

**Tech Stack:** SwiftUI, Foundation (Process, FileManager)

**Spec:** `docs/superpowers/specs/2026-03-15-claude-md-editor-design.md`

---

## Chunk 1: ClaudePathResolver extraction + Kanban setup button

### Task 1: Extract ClaudePathResolver utility

**Files:**
- Create: `Maestro/Services/ClaudePathResolver.swift`
- Modify: `Maestro/Services/AgentRunner.swift:313-350`

- [ ] **Step 1: Create ClaudePathResolver.swift**

```swift
import Foundation

enum ClaudePathResolver {
    static func resolve(preferredPath: String) async -> String {
        // Check if provided path exists
        if FileManager.default.isExecutableFile(atPath: preferredPath) {
            return preferredPath
        }

        // Try common locations
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.claude/local/claude"
        ]

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        // Try `which claude`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {}

        return preferredPath  // Fall back to provided path
    }
}
```

- [ ] **Step 2: Update AgentRunner to use ClaudePathResolver**

In `Maestro/Services/AgentRunner.swift`, replace the private `resolveClaudePath` method (lines 313-350) with a call to the shared utility. Find and replace the two call sites:

```swift
// In start() — line 46:
let resolvedPath = await ClaudePathResolver.resolve(preferredPath: claudePath)

// In resume() — line 89:
let resolvedPath = await ClaudePathResolver.resolve(preferredPath: claudePath)
```

Then delete the entire `private func resolveClaudePath` method (lines 313-350).

- [ ] **Step 3: Add ClaudePathResolver.swift to Xcode project**

```bash
cd /Users/pedrohm/workspace/projects/maestro && xcodegen generate
```

- [ ] **Step 4: Build to verify no regressions**

```bash
cd /Users/pedrohm/workspace/projects/maestro && xcodebuild -scheme Maestro -configuration Debug build 2>&1 | grep -E "error:|BUILD" | tail -10
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
cd /Users/pedrohm/workspace/projects/maestro
git add Maestro/Services/ClaudePathResolver.swift Maestro/Services/AgentRunner.swift
git commit -m "refactor: extract ClaudePathResolver from AgentRunner into shared utility"
```

---

### Task 2: Add kanban setup button with navigation callback

**Files:**
- Modify: `Maestro/Views/Kanban/KanbanBoardView.swift`
- Modify: `Maestro/Views/ContentView.swift:36-39`

- [ ] **Step 1: Add onNavigateToSettings callback to KanbanBoardView**

In `Maestro/Views/Kanban/KanbanBoardView.swift`, add the callback property and update the init:

```swift
// Add below existing onNavigateToRun (line 11):
var onNavigateToSettings: (() -> Void)?

// Replace init (lines 13-21) with:
init(project: Project, onNavigateToRun: ((String) -> Void)? = nil, onNavigateToSettings: (() -> Void)? = nil) {
    self.project = project
    self.onNavigateToRun = onNavigateToRun
    self.onNavigateToSettings = onNavigateToSettings
    let projectId = project.id
    _tasks = Query(
        filter: #Predicate<ProjectTask> { $0.project?.id == projectId && $0.isArchived == false },
        sort: [SortDescriptor(\.order)]
    )
}
```

- [ ] **Step 2: Add claudeMDExists state and setup button in toolbar**

In `Maestro/Views/Kanban/KanbanBoardView.swift`, add state variable:

```swift
// Add below existing @State properties (after line 10):
@State private var claudeMDExists: Bool = true  // default true to avoid flash
```

Replace the existing `.toolbar` block (lines 52-58) with:

```swift
.toolbar {
    ToolbarItem(placement: .automatic) {
        if !claudeMDExists && !project.workspaceRoot.isEmpty {
            Button {
                onNavigateToSettings?()
            } label: {
                Label("Set up CLAUDE.md", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    ToolbarItem(placement: .automatic) {
        Button(action: { showingNewTask = true }) {
            Label("New Task", systemImage: "plus")
        }
    }
}
```

Add an `.onAppear` modifier to check file existence. Add it right after the existing `.animation` modifier (line 73):

```swift
.onAppear {
    claudeMDExists = !project.workspaceRoot.isEmpty &&
        FileManager.default.fileExists(atPath: "\(project.workspaceRoot)/CLAUDE.md")
}
```

- [ ] **Step 3: Wire onNavigateToSettings in ContentView**

In `Maestro/Views/ContentView.swift`, update the two `KanbanBoardView` call sites (lines 36-39 and 47-49) to pass the new callback:

```swift
// Line 36-39 — replace:
KanbanBoardView(project: project, onNavigateToRun: { runId in
    activitySelectedRunId = runId
    selectedNav = .activity
}, onNavigateToSettings: {
    selectedNav = .settings
})

// Line 47-49 — replace (the nil case duplicate):
KanbanBoardView(project: project, onNavigateToRun: { runId in
    activitySelectedRunId = runId
    selectedNav = .activity
}, onNavigateToSettings: {
    selectedNav = .settings
})
```

- [ ] **Step 4: Build to verify**

```bash
cd /Users/pedrohm/workspace/projects/maestro && xcodebuild -scheme Maestro -configuration Debug build 2>&1 | grep -E "error:|BUILD" | tail -10
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
cd /Users/pedrohm/workspace/projects/maestro
git add Maestro/Views/Kanban/KanbanBoardView.swift Maestro/Views/ContentView.swift
git commit -m "feat: add CLAUDE.md setup button in kanban toolbar with navigation to settings"
```

---

## Chunk 2: CLAUDE.md editor section in ProjectSettingsView

### Task 3: Add CLAUDE.md editor section with file read/write and template

**Files:**
- Modify: `Maestro/Views/Settings/ProjectSettingsView.swift`

This task adds the section with the editor, save button, and template — everything except the "Generate with Claude" button (Task 4).

- [ ] **Step 1: Add state variables and computed properties**

In `Maestro/Views/Settings/ProjectSettingsView.swift`, add these state variables after the existing `@State private var showAllArchived` (line 8):

```swift
@State private var claudeMDContent: String = ""
@State private var savedClaudeMDContent: String = ""
@State private var claudeMDFileExists: Bool = false
@State private var isGenerating: Bool = false
@State private var generationError: String?
@State private var generateTask: Task<Void, Never>?
@State private var generationProcess: Process?
@State private var showTemplateConfirmation: Bool = false
@State private var showGenerateConfirmation: Bool = false
```

Add the environment for orchestrator, after the existing `@Environment(\.modelContext)` (line 7):

```swift
@Environment(AgentOrchestrator.self) private var orchestrator
```

Add computed properties after the existing `archivedTasks` computed property (after line 23):

```swift
private var claudeMDPath: String {
    "\(project.workspaceRoot)/CLAUDE.md"
}

private var isClaudeMDDirty: Bool {
    claudeMDContent != savedClaudeMDContent
}

private var showClaudeMDEditor: Bool {
    claudeMDFileExists || !claudeMDContent.isEmpty
}

private var hasValidWorkspace: Bool {
    !project.workspaceRoot.isEmpty &&
    FileManager.default.fileExists(atPath: project.workspaceRoot)
}
```

- [ ] **Step 2: Add the CLAUDE.md section to the form body**

In `Maestro/Views/Settings/ProjectSettingsView.swift`, insert a new section between the "Usage" section (ends around line 120) and the "Workflow Prompt" section (starts at line 122). Add this after the Usage section's closing brace:

```swift
Section("CLAUDE.md") {
    if !hasValidWorkspace {
        Text("Set a workspace root path first.")
            .font(.caption)
            .foregroundStyle(.secondary)
    } else if showClaudeMDEditor {
        TextEditor(text: $claudeMDContent)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 200)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

        // Status line
        Group {
            if let error = generationError {
                Text(error)
                    .foregroundStyle(.red)
            } else if isGenerating {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating...")
                }
            } else if isClaudeMDDirty {
                Text("Unsaved changes")
                    .foregroundStyle(.orange)
            } else {
                Text("Saved")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)

        HStack {
            Button("Save") {
                saveClaudeMD()
            }
            .disabled(!isClaudeMDDirty || isGenerating)

            Button("New from Template") {
                if isClaudeMDDirty {
                    showTemplateConfirmation = true
                } else {
                    applyTemplate()
                }
            }
            .disabled(isGenerating)

            Button {
                if isClaudeMDDirty {
                    showGenerateConfirmation = true
                } else {
                    generateClaudeMD()
                }
            } label: {
                if isGenerating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Generating...")
                    }
                } else {
                    Text("Generate with Claude")
                }
            }
            .disabled(isGenerating)
        }

        Text("This file is read automatically by Claude agents working in this project's workspace.")
            .font(.caption)
            .foregroundStyle(.secondary)
    } else {
        Text("No CLAUDE.md found in workspace. This file gives agents instant context about your project so they skip exploration and start working immediately.")
            .font(.caption)
            .foregroundStyle(.secondary)

        HStack {
            Button("New from Template") {
                applyTemplate()
            }

            Button("Generate with Claude") {
                generateClaudeMD()
            }
        }
    }
}
```

Then move the lifecycle modifiers and alerts onto the `Form` — **not** on the `Section` (alerts on `Section` inside `.formStyle(.grouped)` won't present reliably on macOS). In the existing `body`, the `Form` already ends with `.formStyle(.grouped)` and `.navigationTitle(...)`. Add these modifiers after `.navigationTitle("Project Settings")`:

```swift
.onAppear {
    loadClaudeMD()
}
.onDisappear {
    if isGenerating {
        generateTask?.cancel()
        generationProcess?.terminate()
        isGenerating = false
    }
}
.alert("Replace unsaved changes with template?", isPresented: $showTemplateConfirmation) {
    Button("Replace", role: .destructive) { applyTemplate() }
    Button("Cancel", role: .cancel) {}
}
.alert("Replace unsaved changes? Claude will generate new content.", isPresented: $showGenerateConfirmation) {
    Button("Replace", role: .destructive) { generateClaudeMD() }
    Button("Cancel", role: .cancel) {}
}
```

- [ ] **Step 3: Add helper methods**

Add these private methods at the bottom of `ProjectSettingsView`, before the closing brace of the struct (before the existing `archivedPriorityColor` method):

```swift
private func loadClaudeMD() {
    let path = claudeMDPath
    if FileManager.default.fileExists(atPath: path),
       let content = try? String(contentsOfFile: path, encoding: .utf8) {
        claudeMDContent = content
        savedClaudeMDContent = content
        claudeMDFileExists = true
    } else {
        claudeMDFileExists = false
    }
}

private func saveClaudeMD() {
    do {
        try claudeMDContent.write(toFile: claudeMDPath, atomically: true, encoding: .utf8)
        savedClaudeMDContent = claudeMDContent
        claudeMDFileExists = true
        generationError = nil
    } catch {
        generationError = "Failed to save: \(error.localizedDescription)"
    }
}

private func applyTemplate() {
    claudeMDContent = """
    # \(project.name)

    [Brief description of what this project does]

    ## Tech Stack

    - ...

    ## Project Structure

    [Key directories and what lives where]

    ## Build Commands

    ```sh
    # How to build
    # How to test
    ```

    ## Key Architecture Decisions

    - ...

    ## Conventions

    - ...
    """
    generationError = nil
}

private func generateClaudeMD() {
    // Implemented in Task 4
}
```

- [ ] **Step 4: Build to verify**

```bash
cd /Users/pedrohm/workspace/projects/maestro && xcodebuild -scheme Maestro -configuration Debug build 2>&1 | grep -E "error:|BUILD" | tail -10
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
cd /Users/pedrohm/workspace/projects/maestro
git add Maestro/Views/Settings/ProjectSettingsView.swift
git commit -m "feat: add CLAUDE.md editor section with save and template support"
```

---

### Task 4: Implement "Generate with Claude" functionality

**Files:**
- Modify: `Maestro/Views/Settings/ProjectSettingsView.swift`

- [ ] **Step 1: Replace the stub generateClaudeMD method**

In `Maestro/Views/Settings/ProjectSettingsView.swift`, replace the `generateClaudeMD()` stub with the full implementation:

```swift
private func generateClaudeMD() {
    isGenerating = true
    generationError = nil

    let workspacePath = project.workspaceRoot
    let claudePath = orchestrator.claudePath

    generateTask = Task {
        let resolvedPath = await ClaudePathResolver.resolve(preferredPath: claudePath)

        let prompt = """
        Analyze this codebase and generate a CLAUDE.md file that will give AI coding agents instant context about this project. Output ONLY the raw markdown content with no preamble or explanation.

        Cover these sections:
        - Project name and one-paragraph description of what it does
        - Tech stack (languages, frameworks, key dependencies)
        - Project structure (key directories and what lives where)
        - Build commands (how to build, test, run)
        - Key architecture decisions
        - Conventions (naming, patterns, anything non-obvious)

        Be concise and specific. Focus on information that would help an agent start working immediately without exploring the codebase first.
        """

        let proc = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let shellCmd = [resolvedPath, "-p", prompt, "--output-format", "text", "--max-turns", "5", "--allowedTools", "Bash,Read,Glob,Grep"]
            .map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")

        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", shellCmd]
        proc.currentDirectoryURL = URL(fileURLWithPath: workspacePath)
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

        await MainActor.run {
            self.generationProcess = proc
        }

        do {
            try proc.run()
        } catch {
            await MainActor.run {
                self.generationError = "Failed to start Claude: \(error.localizedDescription)"
                self.isGenerating = false
                self.generationProcess = nil
            }
            return
        }

        // Read stdout and stderr concurrently to avoid pipe buffer deadlock
        // (if one pipe fills while the other is being read, the process blocks)
        var stderrData = Data()
        let stderrQueue = DispatchQueue(label: "claudemd.stderr")
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stderrPipe.fileHandleForReading.readabilityHandler = nil
            } else {
                stderrQueue.sync { stderrData.append(data) }
            }
        }

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        // Collect stderr
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        let errorOutput = stderrQueue.sync {
            String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        // Trim whitespace and strip any preamble before the first markdown heading
        var output = String(data: stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let headingRange = output.range(of: "(?m)^#", options: .regularExpression) {
            output = String(output[headingRange.lowerBound...])
        }

        await MainActor.run {
            self.generationProcess = nil

            if Task.isCancelled {
                self.isGenerating = false
                return
            }

            if proc.terminationStatus != 0 {
                let errorSuffix = errorOutput.isEmpty ? "" : ": \(String(errorOutput.suffix(200)))"
                self.generationError = "Claude exited with code \(proc.terminationStatus)\(errorSuffix)"
            } else if output.isEmpty {
                self.generationError = "Claude produced no output"
            } else {
                self.claudeMDContent = output
                self.generationError = nil
            }

            self.isGenerating = false
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/pedrohm/workspace/projects/maestro && xcodebuild -scheme Maestro -configuration Debug build 2>&1 | grep -E "error:|BUILD" | tail -10
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
cd /Users/pedrohm/workspace/projects/maestro
git add Maestro/Views/Settings/ProjectSettingsView.swift
git commit -m "feat: implement Generate with Claude for CLAUDE.md creation"
```

---

## Chunk 3: Regenerate Xcode project and final verification

### Task 5: Final Xcode project regeneration and build verification

**Files:**
- Modify: `Maestro.xcodeproj/` (auto-generated)

- [ ] **Step 1: Regenerate Xcode project**

Ensure the project file is up to date after all changes (ClaudePathResolver.swift was added in Chunk 1):

```bash
cd /Users/pedrohm/workspace/projects/maestro && xcodegen generate
```

Expected: `Generated project ... Maestro.xcodeproj`

- [ ] **Step 2: Full clean build**

```bash
cd /Users/pedrohm/workspace/projects/maestro && xcodebuild -scheme Maestro -configuration Debug build 2>&1 | grep -E "error:|BUILD" | tail -10
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit project file if changed**

```bash
cd /Users/pedrohm/workspace/projects/maestro
git add Maestro.xcodeproj/
git commit -m "chore: regenerate Xcode project with ClaudePathResolver"
```

---

### Task 6: Manual smoke test checklist

These are manual verification steps to run the app and confirm everything works.

- [ ] **Step 1: Launch the app and open a project with a workspace root set**

- [ ] **Step 2: Verify kanban — if no CLAUDE.md exists in the workspace, the "Set up CLAUDE.md" sparkles button should appear in the toolbar**

- [ ] **Step 3: Click the sparkles button — should navigate to project settings**

- [ ] **Step 4: In project settings, scroll to the CLAUDE.md section (below Usage). Should show the "No CLAUDE.md found" message with two buttons.**

- [ ] **Step 5: Click "New from Template" — editor should appear with template content, status should show "Unsaved changes"**

- [ ] **Step 6: Click "Save" — status should change to "Saved", file should exist at `{workspaceRoot}/CLAUDE.md`**

- [ ] **Step 7: Edit some text — status should change to "Unsaved changes", Save button should enable**

- [ ] **Step 8: Navigate back to kanban — the sparkles button should no longer appear**

- [ ] **Step 9: Go back to settings, verify the saved content loads correctly in the editor**

- [ ] **Step 10: Test "Generate with Claude" — should show spinner, then populate editor with AI-generated content (requires Claude CLI installed and API key configured)**
