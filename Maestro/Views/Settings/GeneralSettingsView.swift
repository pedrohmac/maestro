import SwiftUI
import MaestroCore

struct GeneralSettingsView: View {
    @Environment(AgentOrchestrator.self) private var orchestrator
    @Environment(AppState.self) private var appState
    @State private var showingLicenseSheet = false
    @State private var claudePath: String = ""
    @State private var maxConcurrency: Int = 3
    @State private var detectedPath: String? = nil

    var body: some View {
        Form {
            Section("License") {
                HStack {
                    if appState.isActivated {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text("Licensed")
                                .fontWeight(.medium)
                            if let key = appState.currentLicenseKey {
                                Text(maskedKey(key))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Deactivate") {
                            Task { await appState.deactivateLicense() }
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Image(systemName: "key")
                            .foregroundStyle(.secondary)
                        Text(appState.trialStatusText)
                            .foregroundStyle(appState.isReadOnly ? .red : .secondary)
                        Spacer()
                        Button("Activate License") {
                            showingLicenseSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            Section("Claude CLI") {
                HStack {
                    TextField("Claude Path", text: $claudePath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            claudePath = url.path
                        }
                    }

                    Button("Detect") {
                        detectClaude()
                    }
                }

                if let detected = detectedPath {
                    Text("Detected: \(detected)")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section("Agent Defaults") {
                Stepper("Max Concurrent Agents: \(maxConcurrency)", value: $maxConcurrency, in: 1...10)

                Text("Controls how many Claude agents can run simultaneously across all projects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Maestro CLI") {
                HStack {
                    if cliInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Installed at /usr/local/bin/maestro")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Uninstall") {
                            uninstallCLI()
                        }
                        Button("Reinstall") {
                            installCLI()
                        }
                    } else {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                        Text("Not installed")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Install CLI") {
                            installCLI()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if let cliMessage = cliStatusMessage {
                    Text(cliMessage)
                        .font(.caption)
                        .foregroundStyle(cliMessageIsError ? .red : .green)
                }

                Text("Installs the `maestro` command to /usr/local/bin so you can manage projects and tasks from the terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Save") {
                        orchestrator.claudePath = claudePath
                        orchestrator.defaultMaxConcurrency = maxConcurrency
                        orchestrator.saveSettings()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingLicenseSheet) {
            LicenseActivationSheet()
        }
        .padding()
        .onAppear {
            claudePath = orchestrator.claudePath
            maxConcurrency = orchestrator.defaultMaxConcurrency
            checkCLIInstalled()
        }
    }

    @State private var cliInstalled: Bool = false
    @State private var cliStatusMessage: String? = nil
    @State private var cliMessageIsError: Bool = false

    private let cliInstallPath = "/usr/local/bin/maestro"

    private func checkCLIInstalled() {
        cliInstalled = FileManager.default.isExecutableFile(atPath: cliInstallPath)
    }

    private func installCLI() {
        cliStatusMessage = nil

        guard let bundledCLI = Bundle.main.url(forResource: "maestro", withExtension: nil) else {
            cliStatusMessage = "CLI binary not found in app bundle. Try rebuilding the app."
            cliMessageIsError = true
            return
        }

        let destination = URL(fileURLWithPath: cliInstallPath)
        let fm = FileManager.default

        do {
            // Ensure /usr/local/bin exists
            let parentDir = destination.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDir.path) {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            // Remove existing file if present
            if fm.fileExists(atPath: cliInstallPath) {
                try fm.removeItem(at: destination)
            }

            try fm.copyItem(at: bundledCLI, to: destination)

            // Ensure executable permission
            try fm.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: cliInstallPath
            )

            cliInstalled = true
            cliStatusMessage = "CLI installed successfully. Run `maestro --help` to get started."
            cliMessageIsError = false
        } catch {
            cliStatusMessage = "Failed to install: \(error.localizedDescription)"
            cliMessageIsError = true
        }
    }

    private func uninstallCLI() {
        do {
            try FileManager.default.removeItem(atPath: cliInstallPath)
            cliInstalled = false
            cliStatusMessage = "CLI uninstalled."
            cliMessageIsError = false
        } catch {
            cliStatusMessage = "Failed to uninstall: \(error.localizedDescription)"
            cliMessageIsError = true
        }
    }

    private func maskedKey(_ key: String) -> String {
        guard key.count > 8 else { return key }
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    private func detectClaude() {
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.claude/local/claude"
        ]

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                detectedPath = candidate
                claudePath = candidate
                return
            }
        }

        // Try which
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
                detectedPath = path
                claudePath = path
                return
            }
        } catch {}

        detectedPath = nil
    }
}
