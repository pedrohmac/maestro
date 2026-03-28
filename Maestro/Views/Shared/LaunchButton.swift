import SwiftUI
import MaestroCore

struct LaunchButton: View {
    let project: Project
    @Environment(ProjectLauncher.self) private var launcher
    @State private var showingPopover = false
    @State private var hasConfig = false

    private var isThisProjectLaunching: Bool {
        launcher.isLaunching && launcher.launchedProjectId == project.id
    }

    var body: some View {
        Button {
            if isThisProjectLaunching {
                showingPopover = true
            } else if hasConfig {
                launcher.launch(project: project)
                showingPopover = true
            } else {
                showingPopover = true
            }
        } label: {
            HStack(spacing: 4) {
                if isThisProjectLaunching {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9))
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                }
                Text(isThisProjectLaunching ? "Running" : "Open Project")
                    .font(.system(size: 11))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isThisProjectLaunching ? .orange : .green)
        .popover(isPresented: $showingPopover) {
            LaunchPopoverContent(project: project, hasConfig: hasConfig)
        }
        .onAppear { refreshConfigStatus() }
        .onChange(of: project.id) { refreshConfigStatus() }
        .onChange(of: project.workspaceRoot) { refreshConfigStatus() }
        .onChange(of: launcher.isGeneratingConfig) {
            if !launcher.isGeneratingConfig {
                refreshConfigStatus()
            }
        }
    }

    private func refreshConfigStatus() {
        hasConfig = !project.workspaceRoot.isEmpty &&
            LaunchConfig.load(from: project.workspaceRoot) != nil
    }
}

// MARK: - Popover Content

private struct LaunchPopoverContent: View {
    let project: Project
    let hasConfig: Bool
    @Environment(ProjectLauncher.self) private var launcher

    private var isThisProjectLaunching: Bool {
        launcher.isLaunching && launcher.launchedProjectId == project.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isThisProjectLaunching, let config = launcher.currentConfig {
                launchProgressView(config: config)
            } else if hasConfig, let config = LaunchConfig.load(from: project.workspaceRoot) {
                configPreview(config: config)
            } else {
                noConfigView
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Launch Progress

    @ViewBuilder
    private func launchProgressView(config: LaunchConfig) -> some View {
        HStack {
            Text("Launch Progress")
                .font(.headline)
            Spacer()
            Button {
                launcher.stop()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9))
                    Text("Stop")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }

        ForEach(config.steps) { step in
            HStack(spacing: 8) {
                stepStatusIcon(for: step.id)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(step.name)
                        .font(.system(size: 12))
                    Text(step.command)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }

        if let url = config.openUrl {
            Divider()
            HStack(spacing: 4) {
                Image(systemName: "safari")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(url)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }

        if let error = launcher.launchError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Config Preview (before launching)

    @ViewBuilder
    private func configPreview(config: LaunchConfig) -> some View {
        Text("Launch Configuration")
            .font(.headline)

        ForEach(config.steps) { step in
            HStack(spacing: 8) {
                Image(systemName: step.background ? "arrow.clockwise" : "terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(step.name)
                        .font(.system(size: 12))
                    Text(step.command)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }

        if let url = config.openUrl {
            Divider()
            HStack(spacing: 4) {
                Image(systemName: "safari")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Opens \(url)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }

        Button {
            launcher.launch(project: project)
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text("Launch")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .tint(.green)
    }

    // MARK: - No Config

    @ViewBuilder
    private var noConfigView: some View {
        Text("No Launch Configuration")
            .font(.headline)

        Text("This project doesn't have a launch configuration yet. You can set one up in Project Settings, or let Claude analyze your project and generate one automatically.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if let error = launcher.generationError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stepStatusIcon(for stepId: String) -> some View {
        switch launcher.stepStatuses[stepId] ?? .pending {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14))
        case .running:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 14))
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.quaternary)
                .font(.system(size: 14))
        }
    }
}
