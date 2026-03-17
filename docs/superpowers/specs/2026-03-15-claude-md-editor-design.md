# CLAUDE.md Editor in Project Settings

## Summary

Add a CLAUDE.md management section to project settings with a text editor, explicit save, and two initialization paths (template and AI-generated). Show a setup prompt in the kanban board when no CLAUDE.md exists yet.

## Motivation

Every time a Maestro agent picks up a task, it wastes turns exploring the codebase and introducing itself. A CLAUDE.md file in the workspace root gives agents instant project context. Maestro should make it easy to create and maintain this file.

## Design

### 1. Project Settings Section

**Location:** Below the "Usage" section, above "Workflow Prompt". This groups the two agent-facing content sections (CLAUDE.md and Workflow Prompt) together.

**State management** (all `@State`, no model changes):
- `claudeMDContent: String` — current editor text
- `savedContent: String` — last content read from / written to disk
- `fileExists: Bool` — whether the file exists on disk
- `isGenerating: Bool` — whether Claude is currently generating content
- `generateTask: Task<Void, Never>?` — reference to the generation task for cancellation
- `generationError: String?` — error message from failed generation

**Computed:**
- `isDirty: Bool` — `claudeMDContent != savedContent`
- `showEditor: Bool` — `fileExists || !claudeMDContent.isEmpty` (show editor once content is loaded from any source)

**On appear:** Read `{project.workspaceRoot}/CLAUDE.md` via FileManager. If it exists, load into both `claudeMDContent` and `savedContent`, set `fileExists = true`. Otherwise set `fileExists = false`.

**On disappear:** If `isGenerating`, cancel `generateTask` and terminate the running process.

#### When editor should show (file exists or content has been generated/templated)

- Monospace `TextEditor` showing `claudeMDContent` (same style as Workflow Prompt: `.system(.body, design: .monospaced)`, min height 200, `controlBackgroundColor` rounded rect)
- Status text below editor:
  - "Unsaved changes" (orange) when dirty and not generating
  - "Saved" (secondary) when clean
  - "Generating..." with ProgressView when `isGenerating`
  - Error text (red) when `generationError` is set
- `HStack` of buttons:
  - **Save** — writes `claudeMDContent` to `{workspaceRoot}/CLAUDE.md`, updates `savedContent`, sets `fileExists = true`. Disabled when not dirty or when `isGenerating`.
  - **New from Template** — if `isDirty`, show confirmation alert first ("Replace unsaved changes with template?"). Overwrites `claudeMDContent` with template (see below). Does NOT auto-save. Disabled when `isGenerating`.
  - **Generate with Claude** — if `isDirty`, show confirmation alert first ("Replace unsaved changes?"). Spawns agent (see below), replaces `claudeMDContent` with result. Does NOT auto-save. Disabled when `isGenerating`.
- Caption text: "This file is read automatically by Claude agents working in this project's workspace."

#### When file doesn't exist and no content loaded

- Informational text: "No CLAUDE.md found in workspace. This file gives agents instant context about your project so they skip exploration and start working immediately."
- Two buttons: **New from Template** / **Generate with Claude**
- After either action populates `claudeMDContent`, switch to the editor view

### 2. Template Content

```markdown
# {project.name}

[Brief description of what this project does]

## Tech Stack

- ...

## Project Structure

[Key directories and what lives where]

## Build Commands

\```sh
# How to build
# How to test
\```

## Key Architecture Decisions

- ...

## Conventions

- ...
```

`{project.name}` is interpolated from the Project model. Everything else is placeholder text for the user to fill in.

### 3. Generate with Claude

Spawns a Claude CLI process to analyze the workspace and produce a CLAUDE.md.

**Implementation:** Use `Foundation.Process` directly (not the full `AgentRunner` infrastructure — this is a one-shot text generation, not a tracked agent session). Runs in the project's `workspaceRoot`.

**Claude path resolution:** Extract `resolveClaudePath` from `AgentRunner` into a standalone static utility (e.g. `ClaudePathResolver.resolve(preferredPath:) async -> String`) in `Maestro/Services/`. Both `AgentRunner` and the CLAUDE.md generator will call this utility. The preferred path comes from `AgentOrchestrator.claudePath` — inject the orchestrator via `@Environment(AgentOrchestrator.self) private var orchestrator` in `ProjectSettingsView`.

**Process launch:** Must mirror `AgentRunner.runProcess` to get a working environment:
1. Launch through login shell: `/bin/zsh -l -c "<command>"`
2. Set a clean environment (same as `AgentRunner`):
   ```swift
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
   ```
3. Set `currentDirectoryURL` to the project's `workspaceRoot`

**Command:**
```
claude -p "<prompt>" --output-format text --max-turns 5 --allowedTools "Bash,Read,Glob,Grep"
```

**Prompt:**
```
Analyze this codebase and generate a CLAUDE.md file that will give AI coding agents instant context about this project. Output ONLY the raw markdown content with no preamble or explanation.

Cover these sections:
- Project name and one-paragraph description of what it does
- Tech stack (languages, frameworks, key dependencies)
- Project structure (key directories and what lives where)
- Build commands (how to build, test, run)
- Key architecture decisions
- Conventions (naming, patterns, anything non-obvious)

Be concise and specific. Focus on information that would help an agent start working immediately without exploring the codebase first.
```

**Output handling:** Trim leading/trailing whitespace from stdout. The `--output-format text` flag should produce clean markdown, but strip any leading non-markdown lines if present (e.g. lines before the first `#` heading).

**Error handling:**
- **Process launch failure:** Set `generationError` to the localized error description
- **Non-zero exit code:** Set `generationError` to "Claude exited with code {N}" + last 200 chars of stderr
- **Empty stdout:** Set `generationError` to "Claude produced no output"
- All error paths: set `isGenerating = false`, re-enable buttons

**Lifecycle / cancellation:**
- Store the Swift `Task` in `generateTask` and the `Process` reference in a local variable captured by the task closure
- On `.onDisappear`: cancel `generateTask`, call `process.terminate()` if still running, reset `isGenerating = false`
- On subsequent "Generate" click while already generating: no-op (button is disabled)

**UI during generation:**
- Replace the "Generate with Claude" button label with `ProgressView` spinner + "Generating..."
- Disable Save, New from Template, and Generate with Claude buttons
- On completion: load trimmed stdout into `claudeMDContent`, clear `generationError`, set `isGenerating = false`

### 4. Kanban Setup Button

In `KanbanBoardView`, next to the project name in the toolbar:

- `@State private var claudeMDExists: Bool = false`
- On appear: `claudeMDExists = FileManager.default.fileExists(atPath: "\(project.workspaceRoot)/CLAUDE.md")`
- When `claudeMDExists == false` and `workspaceRoot` is not empty: show a button with `sparkles` SF Symbol and text "Set up CLAUDE.md"
- Button action: call `onNavigateToSettings?()` callback
- Style: `.buttonStyle(.bordered)`, `.controlSize(.small)`

**Navigation wiring:** Add an `onNavigateToSettings: (() -> Void)?` callback parameter to `KanbanBoardView` (matching the existing `onNavigateToRun` pattern). In `ContentView`, pass `onNavigateToSettings: { selectedNav = .settings }`.

The `KanbanBoardView` init becomes:
```swift
init(project: Project,
     onNavigateToRun: ((String) -> Void)? = nil,
     onNavigateToSettings: (() -> Void)? = nil)
```

Place the button in the existing `.toolbar` block alongside the "New Task" button.

### 5. File Operations

All file I/O uses `FileManager.default`:

- **Read:** `String(contentsOfFile: path, encoding: .utf8)`
- **Write:** `content.write(toFile: path, atomically: true, encoding: .utf8)`
- **Exists:** `FileManager.default.fileExists(atPath: path)`

Path: `"\(project.workspaceRoot)/CLAUDE.md"` — no subdirectories created.

Guard against empty `workspaceRoot`: if the workspace root is empty or doesn't exist as a directory, show "Set a workspace root path first" instead of the editor/buttons.

## Files to Modify

1. **`Maestro/Views/Settings/ProjectSettingsView.swift`** — Add CLAUDE.md section with editor, save, template, generate. Add `@Environment(AgentOrchestrator.self)`.
2. **`Maestro/Views/Kanban/KanbanBoardView.swift`** — Add `onNavigateToSettings` callback, setup button in toolbar, `claudeMDExists` state.
3. **`Maestro/Views/ContentView.swift`** — Pass `onNavigateToSettings` closure to `KanbanBoardView` (sets `selectedNav = .settings`).
4. **`Maestro/Services/AgentRunner.swift`** — Extract `resolveClaudePath` to shared utility, replace private method with call to utility.

## Files to Create

1. **`Maestro/Services/ClaudePathResolver.swift`** — Static utility with `static func resolve(preferredPath: String) async -> String`, extracted from `AgentRunner.resolveClaudePath`.

## Out of Scope

- Filesystem watching (no FSEvents / DispatchSource for external edits — refresh on appear is sufficient)
- Storing CLAUDE.md content in SwiftData
- Model migrations
- Editing CLAUDE.md from the kanban view directly (settings only)
