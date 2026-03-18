import Foundation

@MainActor
public final class LicenseManager {
    private let apiClient: LicenseAPIClient
    private let storage: UserDefaults
    private let keychainService: String

    private static let activatedKey = "maestro_license_activated"
    private static let licenseKeychainKey = "license_key"
    private static let instanceKeychainKey = "instance_id"

    public private(set) var isActivated: Bool
    public private(set) var licenseKey: String?

    public init(
        apiClient: LicenseAPIClient = LemonSqueezyClient(),
        storage: UserDefaults = .standard,
        keychainService: String = "com.maestro.app"
    ) {
        self.apiClient = apiClient
        self.storage = storage
        self.keychainService = keychainService

        self.isActivated = storage.bool(forKey: Self.activatedKey)
        if let keyData = KeychainHelper.load(key: Self.licenseKeychainKey, service: keychainService) {
            self.licenseKey = String(data: keyData, encoding: .utf8)
        }
    }

    private var instanceId: String {
        if let data = KeychainHelper.load(key: Self.instanceKeychainKey, service: keychainService),
           let id = String(data: data, encoding: .utf8) {
            return id
        }
        let newId = UUID().uuidString
        KeychainHelper.save(newId.data(using: .utf8)!, key: Self.instanceKeychainKey, service: keychainService)
        return newId
    }

    @discardableResult
    public func activate(key: String) async throws -> Bool {
        let response = try await apiClient.activate(key: key, instanceId: instanceId)

        if response.valid {
            guard KeychainHelper.save(key.data(using: .utf8)!, key: Self.licenseKeychainKey, service: keychainService) else {
                throw LicenseError.keychainWriteFailed
            }
            storage.set(true, forKey: Self.activatedKey)
            self.isActivated = true
            self.licenseKey = key
            return true
        } else {
            return false
        }
    }

    public func deactivate() async throws {
        if let key = licenseKey {
            _ = try await apiClient.deactivate(key: key, instanceId: instanceId)
        }
        clearLocalState()
    }

    @discardableResult
    public func validateCachedLicense() async throws -> Bool {
        guard let key = licenseKey else { return false }

        let response = try await apiClient.validate(key: key, instanceId: instanceId)

        if !response.valid {
            clearLocalState()
            return false
        }
        return true
    }

    private func clearLocalState() {
        KeychainHelper.delete(key: Self.licenseKeychainKey, service: keychainService)
        storage.set(false, forKey: Self.activatedKey)
        self.isActivated = false
        self.licenseKey = nil
    }
}
