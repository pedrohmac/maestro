import Foundation
import MaestroCore

struct PromptBuilder {
    static func build(task: ProjectTask, project: Project, workspacePath: String, previousDiscussion: [TaskComment]? = nil) -> String {
        var parts: [String] = []

        parts.append("""
            ## Agent Instructions
            You are an autonomous AI agent dispatched by Maestro. You must complete your assigned task independently and with diligence. Do NOT use the brainstorm skill or any interactive workflows. Focus on delivering working results.
            """)

        parts.append("# Task: \(task.title)")

        if !task.taskDescription.isEmpty {
            parts.append("\n## Description\n\(task.taskDescription)")
        }

        // Include previous discussion context when re-running a task
        if let discussion = previousDiscussion, !discussion.isEmpty {
            var section = "\n## Previous Discussion\nThis task has been worked on before. Here is the discussion from previous run(s) for context:\n"
            for comment in discussion {
                let author = comment.authorType == .agent ? "Agent" : "User"
                section += "\n**\(author):**\n\(comment.body)\n"
            }
            parts.append(section)
        }

        parts.append("\n## Workspace\nYou are working in: \(workspacePath)")

        if !project.defaultBranch.isEmpty {
            parts.append("\n## Branch\nYou should be working on the `\(project.defaultBranch)` branch.")
        }

        if task.useWorktree {
            let branchName = "maestro/task-\(task.id)"
            parts.append("""

                ## Worktree
                This task is running in an isolated git worktree. When you have completed all your work, you MUST end your final message with a "## How to Test" section that includes:
                - The worktree path: `\(workspacePath)`
                - The branch name: `\(branchName)`
                - Step-by-step commands to navigate there, build, and verify your changes
                """)
        }

        if !project.workflowPrompt.isEmpty {
            parts.append("\n## Workflow Instructions\n\(project.workflowPrompt)")
        }

        // Instruct agents to maintain the launch config when they change how the project runs
        if !project.workspaceRoot.isEmpty {
            parts.append("""

                ## Launch Configuration
                When you make changes that affect how this project is started, tested, or run locally (e.g. adding dependencies, changing ports, adding services, modifying build steps), you MUST update the launch configuration file at `.maestro/launch.json`. This file tells non-technical users how to run the project with a single click. Create the `.maestro` directory if it does not exist.

                The JSON format is:
                ```json
                {
                  "steps": [
                    { "id": "unique-id", "name": "Step name", "command": "shell command", "background": false },
                    { "id": "unique-id", "name": "Start server", "command": "npm run dev", "background": true, "waitSeconds": 3 }
                  ],
                  "openUrl": "http://localhost:3000",
                  "readyCheckUrl": "http://localhost:3000",
                  "readyCheckTimeoutSeconds": 30
                }
                ```
                Steps with `"background": true` run as background processes (servers, watchers). Steps with `"background": false` run sequentially. If `readyCheckUrl` is set, it is polled before opening `openUrl` in the browser.
                """)
        }

        return parts.joined(separator: "\n")
    }

    static func buildResume(task: ProjectTask, followUp: String? = nil) -> String {
        if let followUp = followUp, !followUp.isEmpty {
            return followUp
        }
        return "Continue working on: \(task.title)"
    }
}
