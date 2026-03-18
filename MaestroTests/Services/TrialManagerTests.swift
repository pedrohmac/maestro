import XCTest
@testable import MaestroCore

final class TrialManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.maestro.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    func testNewTrialNotStarted() {
        let manager = TrialManager(storage: defaults, currentDate: { Date() })
        XCTAssertFalse(manager.isTrialStarted)
        XCTAssertFalse(manager.isTrialExpired)
    }

    func testStartTrialSetsStartDate() {
        let now = Date()
        let manager = TrialManager(storage: defaults, currentDate: { now })
        manager.startTrial()
        XCTAssertTrue(manager.isTrialStarted)
        XCTAssertFalse(manager.isTrialExpired)
        XCTAssertEqual(manager.daysRemaining, 3)
    }

    func testTrialExpiresAfterThreeDays() {
        let startDate = Date()
        let manager = TrialManager(storage: defaults, currentDate: { startDate })
        manager.startTrial()

        let fourDaysLater = Calendar.current.date(byAdding: .day, value: 4, to: startDate)!
        let expiredManager = TrialManager(storage: defaults, currentDate: { fourDaysLater })
        XCTAssertTrue(expiredManager.isTrialExpired)
        XCTAssertEqual(expiredManager.daysRemaining, 0)
    }

    func testTrialActiveOnDay2() {
        let startDate = Date()
        let manager = TrialManager(storage: defaults, currentDate: { startDate })
        manager.startTrial()

        let twoDaysLater = Calendar.current.date(byAdding: .day, value: 2, to: startDate)!
        let activeManager = TrialManager(storage: defaults, currentDate: { twoDaysLater })
        XCTAssertFalse(activeManager.isTrialExpired)
        XCTAssertEqual(activeManager.daysRemaining, 1)
    }

    func testDaysRemainingNeverNegative() {
        let startDate = Date()
        let manager = TrialManager(storage: defaults, currentDate: { startDate })
        manager.startTrial()

        let tenDaysLater = Calendar.current.date(byAdding: .day, value: 10, to: startDate)!
        let expiredManager = TrialManager(storage: defaults, currentDate: { tenDaysLater })
        XCTAssertEqual(expiredManager.daysRemaining, 0)
    }

    func testTrialPersistsAcrossInstances() {
        let now = Date()
        let first = TrialManager(storage: defaults, currentDate: { now })
        first.startTrial()

        let second = TrialManager(storage: defaults, currentDate: { now })
        XCTAssertTrue(second.isTrialStarted)
        XCTAssertEqual(second.daysRemaining, 3)
    }

    func testStartTrialIsIdempotent() {
        let startDate = Date()
        let manager = TrialManager(storage: defaults, currentDate: { startDate })
        manager.startTrial()

        let twoDaysLater = Calendar.current.date(byAdding: .day, value: 2, to: startDate)!
        let laterManager = TrialManager(storage: defaults, currentDate: { twoDaysLater })
        laterManager.startTrial()

        XCTAssertEqual(laterManager.daysRemaining, 1)
    }
}
