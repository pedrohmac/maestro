# Maestro

Native macOS app (SwiftUI + SwiftData) that orchestrates Claude AI coding agents. Think "Symphony for Claude" — a Linear-like project management UI (kanban + gantt) that dispatches and manages Claude CLI sessions per task.

## Tech Stack

- **UI:** SwiftUI, macOS 14+ (Sonoma)
- **Data:** SwiftData (not Core Data)
- **Concurrency:** Swift actors + AsyncSemaphore (groue/Semaphore package)
- **CLI:** swift-argument-parser for `maestro` CLI tool
- **Build:** Xcode 16, XcodeGen (`project.yml` → `.xcodeproj`)
- **Distribution:** Non-sandboxed (must spawn CLI tools freely)

## Project Structure

```
Maestro/               # SwiftUI app target
  MaestroApp.swift     # @main entry point
  Services/            # Agent orchestration engine
    AgentOrchestrator.swift  # Main orchestrator
    AgentPool.swift          # Actor: concurrent process slots via AsyncSemaphore
    AgentRunner.swift        # Spawns & manages single claude process (Foundation.Process)
    OutputParser.swift       # Parses claude stream-json NDJSON output
    PromptBuilder.swift      # Constructs prompts from task + project config
    WorkspaceManager.swift   # Git worktree management per task
  Views/
    ContentView.swift        # NavigationSplitView shell
    Sidebar/SidebarView.swift
    Kanban/                  # Drag-and-drop kanban board
    Gantt/                   # Swift Charts-based gantt view
    Activity/                # Live agent session monitoring + interactive chat
    Settings/                # App + per-project settings
    Shared/                  # TaskDetailView, NewTaskSheet, TaskCommentRow

MaestroCore/           # Static library shared between app and CLI
  MaestroStore.swift   # SwiftData store access
  Models/
    Project.swift      # Project grouping (workspace root, agent config)
    ProjectTask.swift  # Core task entity (kanban status, priority, dates)
    AgentRun.swift     # Agent execution record (session ID, log, cost)
    TaskComment.swift  # Task comments
    Enums.swift        # TaskStatus, Priority, RunStatus, WorkspaceStrategy

CLI/                   # `maestro` command-line tool target
  MaestroCLI.swift     # Entry point
  Commands/            # project, task, run, import, export subcommands
  Helpers/             # Resolver, TableFormatter
```

## Build Commands

```sh
# Regenerate .xcodeproj from project.yml (required after adding files/targets)
xcodegen generate

# Build the app
xcodebuild -scheme Maestro -configuration Debug build

# Build just the core library
xcodebuild -scheme MaestroCore -configuration Debug build

# Build just the CLI
xcodebuild -scheme MaestroCLI -configuration Debug build
```

The Maestro app target has a post-build script that copies the `maestro` CLI binary into the app bundle at `Contents/Resources/maestro`.

## Key Architecture Decisions

- **AgentPool** is a Swift actor that manages concurrent Claude process slots using AsyncSemaphore. Tasks queue when slots are full.
- **AgentRunner** uses Foundation.Process with bidirectional streaming (stdin/stdout pipes). Claude runs with `--output-format stream-json --input-format stream-json`. Users can send follow-up messages to running agents via stdin.
- **WorkspaceManager** supports two strategies: shared (all tasks use project root) or isolated (git worktree per task).
- **Three targets:** Maestro (app), MaestroCore (shared library), MaestroCLI (CLI tool). Models live in MaestroCore so both app and CLI can access them.
- SwiftData models use `@Model` macro. The app does NOT use Core Data directly.

## Conventions

- No app sandbox — entitlements explicitly set `com.apple.security.app-sandbox: false`
- Task status flow: todo → inProgress → review → done
- Agent dispatch modes: manual (user clicks Run) or auto (triggered on status change to inProgress)
