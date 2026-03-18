import SwiftUI
import MaestroCore

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var currentStep = 0
    @State private var apiKey = ""

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch currentStep {
                case 0:
                    welcomeStep
                case 1:
                    APIKeySetupView(apiKey: $apiKey)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)

            Divider()

            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { step in
                        Circle()
                            .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                if currentStep == 0 {
                    Button("Get Started") {
                        currentStep = 1
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(apiKey.isEmpty ? "Skip for Now" : "Start Trial") {
                        if !apiKey.isEmpty {
                            KeychainHelper.save(
                                apiKey.data(using: .utf8)!,
                                key: "anthropic_api_key",
                                service: "com.maestro.app"
                            )
                        }
                        appState.startTrial()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 420)
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(.accent)

            Text("Welcome to Maestro")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Manage software projects with AI agents — no coding required.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "rectangle.split.3x1.fill", text: "Organize tasks on a visual board")
                FeatureRow(icon: "bolt.fill", text: "Dispatch AI agents to build your project")
                FeatureRow(icon: "eye.fill", text: "Watch progress in real time")
            }
            .padding(.top, 8)

            Text("You get a free 3-day trial. No credit card needed.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.accent)
                .frame(width: 24)
            Text(text)
        }
    }
}
