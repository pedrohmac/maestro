# Maestro - macOS Native Agent Orchestrator

## Context

Symphony (OpenAI) showed that an orchestration layer that polls issues, spawns coding agents per task, and manages the lifecycle to PR landing is powerful — but it's Codex-only, Elixir-based, and has no UI. We're building **Maestro**, a native macOS app that provides a Linear-like project management UI (kanban + gantt) and orchestrates Claude CLI sessions per task. This gives you a single app to manage work AND dispatch autonomous coding agents.

## Project Location

`/Users/pedrohm/workspace/projects/maestro` — Swift Package / Xcode project

## Tech Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| UI | SwiftUI | Native macOS, modern |
| Data | SwiftData | macOS 14+, simpler than Core Data |
| Navigation | NavigationSplitView | Standard macOS sidebar pattern |
| Kanban DnD | draggable/dropDestination | Native SwiftUI, no deps |
| Gantt | Swift Charts (BarMark) | Lightweight MVP, upgrade to Ganttis later |
| Process mgmt | Foundation Process + Pipe | Stable, well-documented |
| Concurrency | Actor + AsyncSemaphore | Safe process pool pattern |
| Secrets | macOS Keychain | Secure API key storage |
| Distribution | Non-sandboxed | Required to spawn CLI tools freely |

**External dependency:** [groue/Semaphore](https://github.com/groue/Semaphore) for `AsyncSemaphore`

---

## Phase 1: Project Scaffold + Data Model

### 1.1 Create Xcode project
- New SwiftUI macOS app "Maestro" at `/Users/pedrohm/workspace/projects/maestro`
- Target macOS 14.0+ (Sonoma)
- Disable App Sandbox entitlement
- Add Swift Package dependency: `https://github.com/groue/Semaphore` (for AsyncSemaphore)

### 1.2 Data Model (`Models/`)

```
Models/
  ProjectTask.swift    - Main task model
  Project.swift        - Project grouping
  AgentRun.swift       - Agent execution history
  Enums.swift          - TaskStatus, Priority enums
```

**ProjectTask** — core entity:
- `id: String` (UUID)
- `title: String`, `taskDescription: String`
- `status: TaskStatus` (todo, inProgress, review, done)
- `priority: Priority` (low, medium, high, critical)
- `createdDate: Date`, `startDate: Date?`, `dueDate: Date?`, `completedDate: Date?`
- `order: Int` (position within kanban column)
- `project: Project?` (relationship)
- `agentRuns: [AgentRun]` (relationship)
- Conforms to `Transferable` for drag-and-drop

**Project** — groups tasks:
- `id: String`, `name: String`
- `workspaceRoot: String` (directory for Claude to work in)
- `workspaceStrategy: WorkspaceStrategy` (shared / isolated per task)
- `workflowPrompt: String` (template appended to every agent prompt)
- `maxConcurrentAgents: Int` (default 3)
- `defaultAllowedTools: String` (default "Bash,Read,Edit,Write")
- `maxTurns: Int` (default 10)
- `maxBudgetUSD: Double?`
- `tasks: [ProjectTask]`

**AgentRun** — execution record:
- `id: String`, `task: ProjectTask?`
- `sessionId: String?` (Claude session ID for resume)
- `startedAt: Date`, `completedAt: Date?`
- `exitCode: Int?`
- `log: String` (accumulated stdout)
- `status: RunStatus` (running, completed, failed, cancelled, timedOut)
- `tokensUsed: Int?`, `costUSD: Double?`

### 1.3 App Entry Point
- `MaestroApp.swift` with `@main`, `WindowGroup`, SwiftData `ModelContainer`
- Inject shared `AgentOrchestrator` as environment object

---

## Phase 2: Core UI — Sidebar + Kanban

### 2.1 Navigation (`Views/`)
```
Views/
  ContentView.swift       - NavigationSplitView shell
  Sidebar/
    SidebarView.swift     - Project list + view selector (Kanban, Gantt, Activity, Settings)
  Kanban/
    KanbanBoardView.swift - Columns layout
    KanbanColumnView.swift - Single status column with drop target
    TaskCardView.swift    - Draggable card
  Shared/
    TaskDetailView.swift  - Edit task + agent controls
    NewTaskSheet.swift    - Create task modal
```

### 2.2 Kanban Implementation
- `KanbanBoardView`: `HStack` of `KanbanColumnView` for each `TaskStatus`
- `KanbanColumnView`: `ScrollView` > `LazyVStack` of `TaskCardView`, with `.dropDestination(for: ProjectTask.ID.self)` to accept drops
- `TaskCardView`: Shows title, priority badge, agent status indicator. Uses `.draggable(task.id)`
- Reorder within columns via drop position calculation
- Status change on cross-column drop

### 2.3 Task Detail (sheet/inspector)
- Title, description, priority, dates editors
- "Run Agent" button (disabled if agent already running)
- Agent output log (scrollable, monospace text)
- "Resume" button if previous session exists

---

## Phase 3: Gantt View

### 3.1 Gantt Chart (`Views/Gantt/`)
```
Views/Gantt/
  GanttChartView.swift   - Main chart container with time axis
  GanttBarView.swift     - Individual task bar
```

- Use Swift Charts `Chart { ForEach(tasks) { BarMark(...) } }` with horizontal bars
- X-axis: dates (scrollable timeline)
- Y-axis: task titles
- Bar color: status-based (blue=todo, orange=inProgress, purple=review, green=done)
- Click bar to open task detail
- MVP: read-only visualization. Future: drag to adjust dates.

---

## Phase 4: Claude CLI Orchestration Engine

This is the core differentiator. Architecture:

```
Services/
  AgentOrchestrator.swift   - Main orchestrator (dispatch mode, queue)
  AgentRunner.swift         - Spawns & manages a single claude process
  AgentPool.swift           - Actor managing concurrent process slots
  PromptBuilder.swift       - Constructs claude prompt from task + project config
  WorkspaceManager.swift    - Manages workspace directories per task
  OutputParser.swift        - Parses stream-json output from claude
```

### 4.1 AgentPool (Actor)
```swift
actor AgentPool {
    private let semaphore: AsyncSemaphore
    private var activeRunners: [String: AgentRunner] = [:]  // taskId -> runner
    private var queue: [(ProjectTask, Project)] = []

    func submit(task: ProjectTask, project: Project) async
    func cancel(taskId: String) async
    func cancelAll() async
    var activeCount: Int { get }
}
```

### 4.2 AgentRunner
- Creates `Foundation.Process` with **bidirectional streaming**:
  ```
  claude -p "<initial prompt>" \
    --output-format stream-json \
    --input-format stream-json \
    --allowedTools "<tools>" \
    --max-turns <N> \
    --max-budget-usd <N> \
    --append-system-prompt "<workflow>" \
    --verbose
  ```
- Sets `currentDirectoryURL` to workspace path
- **Bidirectional I/O**:
  - stdout Pipe: reads NDJSON lines async, parsed by `OutputParser`
  - stdin Pipe: kept open — user can send follow-up messages as JSON to the running session
  - `sendMessage(_ text: String)` method writes to stdin pipe
- Publishes progress via `AsyncStream<AgentEvent>` consumed by UI
- Handles timeout (configurable, default 30min)
- On completion: stores `session_id` from JSON output for potential `--resume`
- On resume: spawns new process with `--resume <sessionId>` to continue a previous session

### 4.3 PromptBuilder
- Template: `"Task: {title}\n\nDescription: {description}\n\nWorkspace: {path}"`
- Appends project's `workflowPrompt` if set
- Future: support for richer templates with variables

### 4.4 WorkspaceManager
- **Shared strategy**: Uses `project.workspaceRoot` directly
- **Isolated strategy**: Creates `{workspaceRoot}/.maestro-workspaces/{taskId}/` and runs `git worktree add` (or clone)
- Cleanup on task completion (configurable)

### 4.5 Dispatch Modes
- **Manual**: User clicks "Run Agent" on a task
- **Auto-dispatch**: When a task is moved to "In Progress", automatically submit to pool if slots available; queue if full
- Toggle in project settings, stored in `Project` model
- Auto-dispatch respects `maxConcurrentAgents`

### 4.6 OutputParser
Parses Claude's `stream-json` NDJSON output. Each line is a JSON object with fields like:
- `type`: "assistant", "tool_use", "result", etc.
- `message.content`: the actual text/tool output
- Extract: text content, tool calls, session_id, token usage, cost

---

## Phase 5: Agent Activity View + Settings

### 5.1 Agent Activity & Interaction (`Views/Activity/`)
```
Views/Activity/
  AgentActivityView.swift    - List of running/recent agent sessions
  AgentSessionView.swift     - Interactive live session view
```
- Shows all active runners with real-time streaming output
- Progress indicator per session (turn count, elapsed time)
- Cancel button per session
- **Interactive chat input**: text field at the bottom of each session view to send follow-up messages to the running agent (writes to stdin pipe). This lets you steer the agent mid-task — e.g., "focus on the auth module instead" or "skip tests for now"
- **Chat-like layout**: agent output rendered as message bubbles (assistant messages, tool calls shown as collapsible blocks, user follow-ups shown as sent messages)
- **Resume completed sessions**: button to re-spawn claude with `--resume <sessionId>` and continue interacting
- History of completed runs with exit status

### 5.2 Settings (`Views/Settings/`)
```
Views/Settings/
  SettingsView.swift          - Main settings container
  GeneralSettingsView.swift   - Claude path, default concurrency
  ProjectSettingsView.swift   - Per-project: workspace, tools, budget, dispatch mode
```
- Claude CLI path (auto-detect from PATH or manual)
- Default max concurrent agents
- Default allowed tools
- Default max turns / budget
- Per-project overrides

---

## File Structure Summary

```
maestro/
  Maestro/
    MaestroApp.swift
    Models/
      ProjectTask.swift
      Project.swift
      AgentRun.swift
      Enums.swift
    Views/
      ContentView.swift
      Sidebar/
        SidebarView.swift
      Kanban/
        KanbanBoardView.swift
        KanbanColumnView.swift
        TaskCardView.swift
      Gantt/
        GanttChartView.swift
        GanttBarView.swift
      Activity/
        AgentActivityView.swift
        AgentSessionView.swift
      Shared/
        TaskDetailView.swift
        NewTaskSheet.swift
      Settings/
        SettingsView.swift
        GeneralSettingsView.swift
        ProjectSettingsView.swift
    Services/
      AgentOrchestrator.swift
      AgentRunner.swift
      AgentPool.swift
      PromptBuilder.swift
      WorkspaceManager.swift
      OutputParser.swift
    Utilities/
      KeychainHelper.swift
  Package.swift (or .xcodeproj)
```

---

## Implementation Order

1. **Phase 1** — Scaffold + data model (get the app launching with SwiftData)
2. **Phase 2** — Kanban board (core UI, drag-and-drop, CRUD)
3. **Phase 3** — Gantt chart (visualization layer)
4. **Phase 4** — Agent orchestration engine (the core value — Claude spawning)
5. **Phase 5** — Activity view + settings (observability, configuration)

Phases 1-2 deliver a usable task board. Phase 4 is where it becomes "Symphony for Claude."

---

## Verification

After each phase:

- **Phase 1**: App launches, can create/read/update/delete tasks and projects in SwiftData
- **Phase 2**: Kanban board renders tasks in columns, drag-drop changes status, task detail sheet works
- **Phase 3**: Gantt chart shows tasks as horizontal bars positioned by dates
- **Phase 4**: Click "Run Agent" on a task → claude process spawns → output streams to UI → session completes and stores result. Test with a simple prompt like "list files in the workspace"
- **Phase 5**: Settings persist and affect agent behavior, activity view shows live/historical runs. Send a follow-up message to a running agent and verify it responds.

**End-to-end test**: Create a project pointing at a real repo → create a task "Add a hello world endpoint" → click Run Agent → watch Claude work in the Activity view → send a follow-up like "also add a health check endpoint" → see both results. Resume the session later and ask "what did you change?"
