import Foundation
import MaestroCore

struct PromptBuilder {
    static func build(task: ProjectTask, project: Project, workspacePath: String) -> String {
        var parts: [String] = []

        parts.append("""
            ## Agent Instructions
            You are an autonomous AI agent dispatched by Maestro. You must complete your assigned task independently and with diligence. Do NOT use the brainstorm skill or any interactive workflows. Focus on delivering working results.
            """)

        parts.append("# Task: \(task.title)")

        if !task.taskDescription.isEmpty {
            parts.append("\n## Description\n\(task.taskDescription)")
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

        return parts.joined(separator: "\n")
    }

    static func buildResume(task: ProjectTask, followUp: String? = nil) -> String {
        if let followUp = followUp, !followUp.isEmpty {
            return followUp
        }
        return "Continue working on: \(task.title)"
    }
}
