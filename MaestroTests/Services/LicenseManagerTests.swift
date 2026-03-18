import XCTest
@testable import MaestroCore

@MainActor
final class LicenseManagerTests: XCTestCase {
    private var mockClient: MockLicenseAPIClient!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let testKeychainService = "com.maestro.tests.license"

    override func setUp() {
        super.setUp()
        mockClient = MockLicenseAPIClient()
        suiteName = "com.maestro.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        KeychainHelper.delete(key: "license_key", service: testKeychainService)
        KeychainHelper.delete(key: "instance_id", service: testKeychainService)
    }

    private func makeManager() -> LicenseManager {
        LicenseManager(
            apiClient: mockClient,
            storage: defaults,
            keychainService: testKeychainService
        )
    }

    func testInitiallyNotActivated() {
        let manager = makeManager()
        XCTAssertFalse(manager.isActivated)
        XCTAssertNil(manager.licenseKey)
    }

    func testActivateSuccessSetsState() async throws {
        let manager = makeManager()
        let success = try await manager.activate(key: "VALID-KEY")
        XCTAssertTrue(success)
        XCTAssertTrue(manager.isActivated)
        XCTAssertEqual(manager.licenseKey, "VALID-KEY")
        XCTAssertEqual(mockClient.activateCallCount, 1)
    }

    func testActivateFailureDoesNotSetState() async throws {
        mockClient.activateResult = .success(
            LicenseResponse(valid: false, licenseKey: LicenseKeyInfo(key: "bad", status: "inactive"))
        )
        let manager = makeManager()
        let success = try await manager.activate(key: "BAD-KEY")
        XCTAssertFalse(success)
        XCTAssertFalse(manager.isActivated)
    }

    func testActivatedStatePersists() async throws {
        let first = makeManager()
        try await first.activate(key: "PERSIST-KEY")

        let second = makeManager()
        XCTAssertTrue(second.isActivated)
        XCTAssertEqual(second.licenseKey, "PERSIST-KEY")
    }

    func testDeactivateClearsState() async throws {
        let manager = makeManager()
        try await manager.activate(key: "TO-DEACTIVATE")
        try await manager.deactivate()
        XCTAssertFalse(manager.isActivated)
        XCTAssertNil(manager.licenseKey)
    }

    func testValidateCachedLicenseCallsAPI() async throws {
        let manager = makeManager()
        try await manager.activate(key: "CHECK-KEY")

        let valid = try await manager.validateCachedLicense()
        XCTAssertTrue(valid)
        XCTAssertEqual(mockClient.validateCallCount, 1)
    }

    func testValidateInvalidLicenseDeactivates() async throws {
        let manager = makeManager()
        try await manager.activate(key: "REVOKED-KEY")

        mockClient.validateResult = .success(
            LicenseResponse(valid: false, licenseKey: LicenseKeyInfo(key: "REVOKED-KEY", status: "disabled"))
        )

        let valid = try await manager.validateCachedLicense()
        XCTAssertFalse(valid)
        XCTAssertFalse(manager.isActivated)
    }
}
