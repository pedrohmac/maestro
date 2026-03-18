import SwiftUI

struct LicenseActivationSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var licenseKey = ""
    @State private var isActivating = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Activate License")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enter the license key from your purchase email.")
                .foregroundStyle(.secondary)

            TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $licenseKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            if let error = appState.licenseError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isActivating {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Activate") {
                    Task {
                        isActivating = true
                        let success = await appState.activateLicense(key: licenseKey.trimmingCharacters(in: .whitespaces))
                        isActivating = false
                        if success {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty || isActivating)
            }

            Divider()

            HStack {
                Text("Don't have a license?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Buy Maestro — $49") {
                    if let url = URL(string: "https://maestro.lemonsqueezy.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
