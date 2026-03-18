import Foundation

/// Tracks a 3-day trial window. Stores trial start date in UserDefaults.
/// Not @Observable — AppState mirrors its state into tracked stored properties.
public final class TrialManager {
    private static let trialStartKey = "maestro_trial_start"
    private static let trialDurationDays = 3

    private let storage: UserDefaults
    private let currentDate: () -> Date

    public init(
        storage: UserDefaults = .standard,
        currentDate: @escaping () -> Date = { Date() }
    ) {
        self.storage = storage
        self.currentDate = currentDate
    }

    public var isTrialStarted: Bool {
        storage.object(forKey: Self.trialStartKey) != nil
    }

    public var trialStartDate: Date? {
        storage.object(forKey: Self.trialStartKey) as? Date
    }

    public var isTrialExpired: Bool {
        guard let start = trialStartDate else { return false }
        let now = currentDate()
        let elapsed = Calendar.current.dateComponents([.day], from: start, to: now).day ?? 0
        return elapsed >= Self.trialDurationDays
    }

    public var daysRemaining: Int {
        guard let start = trialStartDate else { return 0 }
        let now = currentDate()
        let elapsed = Calendar.current.dateComponents([.day], from: start, to: now).day ?? 0
        return max(0, Self.trialDurationDays - elapsed)
    }

    public func startTrial() {
        guard !isTrialStarted else { return }
        storage.set(currentDate(), forKey: Self.trialStartKey)
    }
}
