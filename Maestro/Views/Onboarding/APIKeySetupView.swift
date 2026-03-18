import SwiftUI

struct APIKeySetupView: View {
    @Binding var apiKey: String
    @State private var showingKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set Up Your Claude API Key")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Maestro uses Claude AI to work on your tasks. You'll need an API key from Anthropic.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, text: "Go to console.anthropic.com and create an account")
                StepRow(number: 2, text: "Navigate to API Keys in your dashboard")
                StepRow(number: 3, text: "Click \"Create Key\" and copy it")
                StepRow(number: 4, text: "Paste it below")
            }

            HStack {
                Group {
                    if showingKey {
                        TextField("sk-ant-...", text: $apiKey)
                    } else {
                        SecureField("sk-ant-...", text: $apiKey)
                    }
                }
                .textFieldStyle(.roundedBorder)

                Button(action: { showingKey.toggle() }) {
                    Image(systemName: showingKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)
            }

            if !apiKey.isEmpty && !apiKey.hasPrefix("sk-ant-") {
                Text("This doesn't look like a Claude API key. Keys usually start with sk-ant-")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text("Your API key is stored locally on your Mac and never sent anywhere except Anthropic's servers.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text)
                .font(.callout)
        }
    }
}
