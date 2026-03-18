import Foundation

// MARK: - Response types

public struct LicenseKeyInfo: Codable, Sendable {
    public let key: String
    public let status: String

    public init(key: String, status: String) {
        self.key = key
        self.status = status
    }
}

public struct LicenseResponse: Codable, Sendable {
    public let valid: Bool
    public let licenseKey: LicenseKeyInfo

    public init(valid: Bool, licenseKey: LicenseKeyInfo) {
        self.valid = valid
        self.licenseKey = licenseKey
    }

    enum CodingKeys: String, CodingKey {
        case valid
        case licenseKey = "license_key"
    }
}

// MARK: - Protocol

public protocol LicenseAPIClient: Sendable {
    func activate(key: String, instanceId: String) async throws -> LicenseResponse
    func validate(key: String, instanceId: String) async throws -> LicenseResponse
    func deactivate(key: String, instanceId: String) async throws -> Bool
}

// MARK: - Lemon Squeezy implementation

public struct LemonSqueezyClient: LicenseAPIClient {
    private let baseURL = "https://api.lemonsqueezy.com/v1/licenses"

    public init() {}

    public func activate(key: String, instanceId: String) async throws -> LicenseResponse {
        try await post(endpoint: "activate", params: [
            "license_key": key,
            "instance_name": instanceId
        ])
    }

    public func validate(key: String, instanceId: String) async throws -> LicenseResponse {
        try await post(endpoint: "validate", params: [
            "license_key": key,
            "instance_id": instanceId
        ])
    }

    public func deactivate(key: String, instanceId: String) async throws -> Bool {
        let _: LicenseResponse = try await post(endpoint: "deactivate", params: [
            "license_key": key,
            "instance_id": instanceId
        ])
        return true
    }

    private func post<T: Decodable>(endpoint: String, params: [String: String]) async throws -> T {
        var request = URLRequest(url: URL(string: "\(baseURL)/\(endpoint)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = params
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LicenseError.networkError
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

public enum LicenseError: Error, LocalizedError {
    case networkError
    case invalidKey
    case activationFailed
    case keychainWriteFailed

    public var errorDescription: String? {
        switch self {
        case .networkError: return "Could not connect to license server. Check your internet connection."
        case .invalidKey: return "Invalid license key. Please check and try again."
        case .activationFailed: return "License activation failed. Please try again."
        case .keychainWriteFailed: return "Failed to save license key securely. Please try again."
        }
    }
}
