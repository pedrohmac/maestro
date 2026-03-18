import Foundation
import MaestroCore

@MainActor
@Observable
final class AppState {
    let trialManager: TrialManager
    let licenseManager: LicenseManager

    // Mirrored stored properties — SwiftUI tracks these via @Observable
    private(set) var isTrialStarted: Bool = false
    private(set) var isTrialExpired: Bool = false
    private(set) var daysRemaining: Int = 0
    private(set) var isActivated: Bool = false
    private(set) var currentLicenseKey: String? = nil

    var isShowingOnboarding: Bool = false
    var licenseError: String? = nil

    nonisolated(unsafe) private var refreshTask: Task<Void, Never>?

    init(
        trialManager: TrialManager? = nil,
        licenseManager: LicenseManager? = nil
    ) {
        self.trialManager = trialManager ?? TrialManager()
        self.licenseManager = licenseManager ?? LicenseManager()
        refresh()
        self.isShowingOnboarding = !isTrialStarted && !isActivated
        startPeriodicRefresh()
    }

    // MARK: - Computed (reads tracked stored properties, so @Observable works)

    var isReadOnly: Bool {
        isTrialExpired && !isActivated
    }

    var canRunAgents: Bool {
        !isReadOnly
    }

    var shouldShowTrialBanner: Bool {
        isTrialStarted && !isActivated
    }

    var trialStatusText: String {
        if isActivated {
            return "Licensed"
        } else if !isTrialStarted {
            return "Not started"
        } else if isTrialExpired {
            return "Trial expired"
        } else {
            return "\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") remaining"
        }
    }

    // MARK: - Actions

    func startTrial() {
        trialManager.startTrial()
        refresh()
        isShowingOnboarding = false
    }

    func activateLicense(key: String) async -> Bool {
        licenseError = nil
        do {
            let success = try await licenseManager.activate(key: key)
            refresh()
            if !success {
                licenseError = "Invalid license key. Please check and try again."
            }
            return success
        } catch {
            licenseError = error.localizedDescription
            return false
        }
    }

    func deactivateLicense() async {
        try? await licenseManager.deactivate()
        refresh()
    }

    func validateOnLaunch() async {
        guard isActivated else { return }
        _ = try? await licenseManager.validateCachedLicense()
        refresh()
    }

    // MARK: - Sync

    func refresh() {
        isTrialStarted = trialManager.isTrialStarted
        isTrialExpired = trialManager.isTrialExpired
        daysRemaining = trialManager.daysRemaining
        isActivated = licenseManager.isActivated
        currentLicenseKey = licenseManager.licenseKey
    }

    private func startPeriodicRefresh() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                self?.refresh()
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }
}
