# Maestro

**Manage software projects with AI agents — no coding required.**

Maestro is a native macOS app that gives you a visual project board (kanban + timeline) backed by autonomous AI coding agents. Describe what you want built, drag tasks through columns, and watch AI agents write code, run tests, and commit changes in real time.

![Maestro Demo](maestro.gif)

## Features

- **Visual Kanban Board** — Drag-and-drop task management with Todo, In Progress, Review, and Done columns
- **AI Agent Orchestration** — Dispatch Claude AI agents that read your project, write code, and commit changes autonomously
- **Live Agent Activity** — Watch agents work in real time with a chat-like interface. Send follow-up instructions mid-task.
- **Git Integration** — Branch visualization, worktree-per-task isolation, commit tracking
- **Project Timeline** — Visual story of how your project evolved over time
- **Multi-Project Support** — Manage multiple projects with per-project settings and agent configurations
- **Interactive Chat** — Communicate with running agents to steer their work

## Requirements

- macOS 14.0+ (Sonoma)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and configured in your terminal — Maestro spawns Claude Code processes to run agents, so it must be available in your PATH and authenticated with your Anthropic account

## Quick Start

### Download

Get the latest release from [getmaestro.dev](https://getmaestro.dev).

### Build from Source

```bash
brew install xcodegen
git clone https://github.com/pedrohmac/maestro.git
cd maestro
xcodegen generate
open Maestro.xcodeproj
```

Build and run the **Maestro** scheme in Xcode.

### First Run

1. Open Maestro
2. Go to Settings and set your Claude CLI path (auto-detected if Claude is in your PATH)
3. Create a project and point it to a workspace directory
4. Add a task and click **Run Agent**

## How It Works

1. **Describe** — Write what you want built in plain English
2. **Dispatch** — Maestro assigns your task to an AI agent powered by Claude
3. **Review** — See what the agent changed, approve or roll back

Agents run as Claude CLI processes with bidirectional streaming. You can send follow-up messages to running agents, resume completed sessions, and manage multiple concurrent agents per project.

## Architecture

- **UI:** SwiftUI, macOS 14+
- **Data:** SwiftData
- **Concurrency:** Swift actors + [AsyncSemaphore](https://github.com/groue/Semaphore)
- **Agent Engine:** Foundation.Process with `--output-format stream-json`
- **Build:** XcodeGen (`project.yml`)

Three targets: **Maestro** (app), **MaestroCore** (shared library), **MaestroCLI** (CLI tool).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for build instructions and guidelines.

## License

[MIT License](LICENSE)
