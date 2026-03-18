import SwiftUI

struct TrialBannerView: View {
    @Environment(AppState.self) private var appState
    @State private var showingLicenseSheet = false

    var body: some View {
        if appState.shouldShowTrialBanner {
            HStack(spacing: 12) {
                if appState.isReadOnly {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.white)
                    Text("Trial expired — Activate a license to run AI agents")
                        .font(.callout)
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.white)
                    Text("Trial: \(appState.trialStatusText)")
                        .font(.callout)
                        .foregroundStyle(.white)
                }

                Spacer()

                Button("Buy License") {
                    if let url = URL(string: "https://maestro.lemonsqueezy.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button("Activate") {
                    showingLicenseSheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(appState.isReadOnly ? Color.red.opacity(0.85) : Color.orange.opacity(0.85))
            .sheet(isPresented: $showingLicenseSheet) {
                LicenseActivationSheet()
            }
        }
    }
}
