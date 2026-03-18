import Foundation
@testable import MaestroCore

final class MockLicenseAPIClient: LicenseAPIClient, @unchecked Sendable {
    var activateResult: Result<LicenseResponse, Error> = .success(
        LicenseResponse(valid: true, licenseKey: LicenseKeyInfo(key: "test-key", status: "active"))
    )
    var validateResult: Result<LicenseResponse, Error> = .success(
        LicenseResponse(valid: true, licenseKey: LicenseKeyInfo(key: "test-key", status: "active"))
    )
    var deactivateResult: Result<Bool, Error> = .success(true)

    var activateCallCount = 0
    var validateCallCount = 0
    var deactivateCallCount = 0

    func activate(key: String, instanceId: String) async throws -> LicenseResponse {
        activateCallCount += 1
        return try activateResult.get()
    }

    func validate(key: String, instanceId: String) async throws -> LicenseResponse {
        validateCallCount += 1
        return try validateResult.get()
    }

    func deactivate(key: String, instanceId: String) async throws -> Bool {
        deactivateCallCount += 1
        return try deactivateResult.get()
    }
}
