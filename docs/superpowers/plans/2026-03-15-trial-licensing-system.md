# Trial & Licensing System Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 3-day trial, license key activation (via Lemon Squeezy), read-only mode enforcement, and first-launch API key onboarding so Maestro can be sold as a $49 one-time purchase.

**Architecture:** A `TrialManager` tracks the 3-day trial window using UserDefaults. A `LicenseManager` (isolated to `@MainActor`) validates and activates license keys via the Lemon Squeezy REST API, storing the key in macOS Keychain. An `AppState` observable combines both managers by mirroring their state into stored `@Observable` properties, ensuring SwiftUI views react to changes. A `refresh()` method syncs from the underlying managers after every mutation. Read-only mode blocks agent execution (runAgent/resumeAgent) but allows all other app functionality. A first-launch onboarding flow guides non-technical users through API key setup and starts the trial.

**Tech Stack:** Swift 5.9, SwiftUI, macOS Keychain (Security framework), Lemon Squeezy License API (URLSession), UserDefaults, XCTest

**Design decision:** The spec says "Paddle or Lemon Squeezy." This plan implements Lemon Squeezy (simple REST API, no native SDK). The `LicenseAPIClient` protocol allows swapping to Paddle later.

---

## File Structure

**New files (MaestroCore — testable services):**
- `MaestroCore/Services/KeychainHelper.swift` — Keychain CRUD wrapper
- `MaestroCore/Services/TrialManager.swift` — 3-day trial countdown logic
- `MaestroCore/Services/LicenseAPIClient.swift` — Protocol + Lemon Squeezy HTTP implementation
- `MaestroCore/Services/LicenseManager.swift` — License state management

**New files (Maestro app — UI and app-level glue):**
- `Maestro/Services/AppState.swift` — Mirrors trial + license state as stored @Observable properties for SwiftUI
- `Maestro/Views/Onboarding/OnboardingView.swift` — First-launch welcome + API key setup + trial start
- `Maestro/Views/Onboarding/APIKeySetupView.swift` — Step-by-step API key guide
- `Maestro/Views/Shared/TrialBannerView.swift` — Persistent trial countdown / expired banner
- `Maestro/Views/Shared/LicenseActivationSheet.swift` — License key entry and validation

**New files (Tests):**
- `MaestroTests/Helpers/MockLicenseAPIClient.swift` — Shared mock for license API tests
- `MaestroTests/Services/KeychainHelperTests.swift`
- `MaestroTests/Services/TrialManagerTests.swift`
- `MaestroTests/Services/LicenseManagerTests.swift`
- `MaestroTests/Services/AppStateTests.swift`

**Modified files:**
- `project.yml` — Add MaestroTests target, add Security framework to MaestroCore
- `Maestro/MaestroApp.swift` — Initialize AppState, show onboarding on first launch
- `Maestro/Views/ContentView.swift` — Add trial banner, onboarding sheet
- `Maestro/Services/AgentOrchestrator.swift` — Check AppState before running agents
- `Maestro/Views/Shared/TaskDetailView.swift` — Disable Run Agent / Resume buttons in read-only mode
- `Maestro/Views/Settings/GeneralSettingsView.swift` — Add License section

**Prerequisite:** Create directories before adding files:
```bash
mkdir -p MaestroCore/Services MaestroTests/Services MaestroTests/Helpers Maestro/Views/Onboarding
```

---

## Chunk 1: Foundation Services

### Task 1: Add Test Target and Security Framework to project.yml

**Files:**
- Modify: `project.yml`
- Create: `MaestroTests/MaestroTests.swift`

- [ ] **Step 1: Create directories and placeholder test**

```bash
mkdir -p MaestroCore/Services MaestroTests/Services MaestroTests/Helpers Maestro/Views/Onboarding
```

Create `MaestroTests/MaestroTests.swift`:

```swift
import XCTest
@testable import MaestroCore

final class MaestroTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 2: Update project.yml — add Security SDK to MaestroCore and add MaestroTests target**

In the `MaestroCore` target, add a `dependencies` section:

```yaml
    dependencies:
      - sdk: Security.framework
```

Add a new target after `MaestroCLI`:

```yaml
  MaestroTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: MaestroTests
    dependencies:
      - target: MaestroCore
    settings:
      base:
        SWIFT_VERSION: "5.9"
        MACOSX_DEPLOYMENT_TARGET: "14.0"
```

- [ ] **Step 3: Regenerate Xcode project**

Run: `cd /Users/pedrohm/workspace/projects/maestro && xcodegen generate`
Expected: "Project generated" with no errors

- [ ] **Step 4: Build and run placeholder test**

Run: `xcodebuild test -project Maestro.xcodeproj -scheme MaestroTests -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: Test suite passes

- [ ] **Step 5: Commit**

```bash
git add MaestroTests/MaestroTests.swift project.yml
git commit -m "chore: add MaestroTests target and Security framework dependency"
```

---

### Task 2: KeychainHelper

**Files:**
- Create: `MaestroCore/Services/KeychainHelper.swift`
- Create: `MaestroTests/Services/KeychainHelperTests.swift`

- [ ] **Step 1: Write failing tests**

Create `MaestroTests/Services/KeychainHelperTests.swift`:

```swift
import XCTest
@testable import MaestroCore

final class KeychainHelperTests: XCTestCase {
    private let testService = "com.maestro.tests"
    private let testKey = "test-license-key"

    override func tearDown() {
        super.tearDown()
        KeychainHelper.delete(key: testKey, service: testService)
    }

    func testSaveAndLoad() throws {
        let data = "my-secret-key".data(using: .utf8)!
        let saved = KeychainHelper.save(data, key: testKey, service: testService)
        XCTAssertTrue(saved)

        let loaded = KeychainHelper.load(key: testKey, service: testService)
        XCTAssertEqual(loaded, data)
    }

    func testLoadReturnsNilWhenEmpty() {
        let loaded = KeychainHelper.load(key: "nonexistent", service: testService)
        XCTAssertNil(loaded)
    }

    func testDeleteRemovesData() {
        let data = "to-delete".data(using: .utf8)!
        KeychainHelper.save(data, key: testKey, service: testService)
        let deleted = KeychainHelper.delete(key: testKey, service: testService)
        XCTAssertTrue(deleted)

        let loaded = KeychainHelper.load(key: testKey, service: testService)
        XCTAssertNil(loaded)
    }

    func testSaveOverwritesExisting() {
        let first = "first".data(using: .utf8)!
        let second = "second".data(using: .utf8)!

        KeychainHelper.save(first, key: testKey, service: testService)
        KeychainHelper.save(second, key: testKey, service: testService)

        let loaded = KeychainHelper.load(key: testKey, service: testService)
        XCTAssertEqual(loaded, second)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Maestro.xcodeproj -scheme MaestroTests -destination 'platform=macOS' -quiet 2>&1 | tail -10`
Expected: Build failure — `KeychainHelper` not found

- [ ] **Step 3: Implement KeychainHelper**

Create `MaestroCore/Services/KeychainHelper.swift`:

```swift
import Foundation
import Security

public struct KeychainHelper {
    @discardableResult
    public static func save(_ data: Data, key: String, service: String = "com.maestro.app") -> Bool {
        delete(key: key, service: service)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    public static func load(key: String, service: String = "com.maestro.app") -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    public static func delete(key: String, service: String = "com.maestro.app") -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Maestro.xcodeproj -scheme MaestroTests -destination 'platform=macOS' -quiet 2>&1 | tail -10`
Expected: All 4 tests pass

- [ ] **Step 5: Commit**

```bash
git add MaestroCore/Services/KeychainHelper.swift MaestroTests/Services/KeychainHelperTests.swift
git commit -m "feat: add KeychainHelper for secure license key storage"
```

---

### Task 3: TrialManager

**Files:**
- Create: `MaestroCore/Services/TrialManager.swift`
- Create: `MaestroTests/Services/TrialManagerTests.swift`

- [ ] **Step 1: Write failing tests**

Create `MaestroTests/Services/TrialManagerTests.swift`:

```swift
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

        // Two days later, calling startTrial again should NOT reset the clock
        let twoDaysLater = Calendar.current.date(byAdding: .day, value: 2, to: startDate)!
        let laterManager = TrialManager(storage: defaults, currentDate: { twoDaysLater })
        laterManager.startTrial()

        XCTAssertEqual(laterManager.daysRemaining, 1) // still 1, not 3
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Maestro.xcodeproj -scheme MaestroTests -destination 'platform=macOS' -quiet 2>&1 | tail -10`
Expected: Build failure — `TrialManager` not found

- [ ] **Step 3: Implement TrialManager**

Create `MaestroCore/Services/TrialManager.swift`:

```swift
import Foundation

/// Tracks a 3-day trial window. Stores trial start date in UserDefaults.
/// Not @Observable — AppState mirrors its state into tracked stored properties.
/// UserDefaults-based storage is intentionally simple for v1. A technically
/// savvy user can reset via `defaults delete`, but the target audience is
/// non-technical. Keychain-based hardening is a future consideration.
public final class TrialManager {
    private static let trialStartKey = "maestro_trial_start"
    private static let trialDurationDays = 3

    private let storage: UserDefaults
    private let currentDate: @Sendable () -> Date

    public init(
        storage: UserDefaults = .standard,
        currentDate: @escaping @Sendable () -> Date = { Date() }
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Maestro.xcodeproj -scheme MaestroTests -destination 'platform=macOS' -quiet 2>&1 | tail -10`
Expected: All 7 TrialManager tests pass

- [ ] **Step 5: Commit**

```bash
git add MaestroCore/Services/TrialManager.swift MaestroTests/Services/TrialManagerTests.swift
git commit -m "feat: add TrialManager with 3-day trial logic"
```

---

### Task 4: LicenseAPIClient and LicenseManager

**Files:**
- Create: `MaestroCore/Services/LicenseAPIClient.swift`
- Create: `MaestroCore/Services/LicenseManager.swift`
- Create: `MaestroTests/Helpers/MockLicenseAPIClient.swift`
- Create: `MaestroTests/Services/LicenseManagerTests.swift`

- [ ] **Step 1: Create shared mock**

Create `MaestroTests/Helpers/MockLicenseAPIClient.swift`:

```swift
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
```

- [ ] **Step 2: Write failing tests**

Create `MaestroTests/Services/LicenseManagerTests.swift`:

```swift
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild test -project Maestro.xcodeproj -scheme MaestroTests -destination 'platform=macOS' -quiet 2>&1 | tail -10`
Expected: Build failure — `LicenseAPIClient`, `LicenseManager`, `LicenseResponse` not found

- [ ] **Step 4: Implement LicenseAPIClient protocol and Lemon Squeezy implementation**

Create `MaestroCore/Services/LicenseAPIClient.swift`:

```swift
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

// NOTE: The Lemon Squeezy API response may nest fields differently than modeled here.
// The response structure should be verified against the actual API during integration testing.
// The activation response includes an "instance" object with an "id" field that is needed
// for subsequent validate/deactivate calls. Adjust the response model as needed.

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
        // Note: validate/deactivate use instance_id (returned from activate), not instance_name
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
        // Lemon Squeezy returns HTTP 200 on successful deactivation
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
```

- [ ] **Step 5: Implement LicenseManager**

Create `MaestroCore/Services/LicenseManager.swift`:

```swift
import Foundation

/// Manages license key activation, validation, and persistence.
/// Isolated to @MainActor to prevent data races on mutable state.
/// Not @Observable — AppState mirrors its state into tracked stored properties.
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

        // Load cached state
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
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild test -project Maestro.xcodeproj -scheme MaestroTests -destination 'platform=macOS' -quiet 2>&1 | tail -10`
Expected: All 7 LicenseManager tests + previous tests pass

- [ ] **Step 7: Commit**

```bash
git add MaestroCore/Services/LicenseAPIClient.swift MaestroCore/Services/LicenseManager.swift MaestroTests/Helpers/MockLicenseAPIClient.swift MaestroTests/Services/LicenseManagerTests.swift
git commit -m "feat: add LicenseManager with Lemon Squeezy API integration"
```

---

### Task 5: AppState

**Files:**
- Create: `Maestro/Services/AppState.swift`
- Create: `MaestroTests/Services/AppStateTests.swift`

- [ ] **Step 1: Write tests for the core logic**

Create `MaestroTests/Services/AppStateTests.swift`:

```swift
import XCTest
@testable import MaestroCore

/// Tests validate the core logic that AppState will encapsulate.
/// AppState itself lives in the Maestro app target and uses @Observable to mirror
/// state from TrialManager and LicenseManager into stored properties that SwiftUI
/// can track. These tests verify the underlying logic is correct.
@MainActor
final class AppStateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var mockClient: MockLicenseAPIClient!
    private let testKeychainService = "com.maestro.tests.appstate"

    override func setUp() {
        super.setUp()
        suiteName = "com.maestro.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        mockClient = MockLicenseAPIClient()
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        KeychainHelper.delete(key: "license_key", service: testKeychainService)
        KeychainHelper.delete(key: "instance_id", service: testKeychainService)
    }

    func testNotReadOnlyDuringActiveTrial() {
        let trial = TrialManager(storage: defaults, currentDate: { Date() })
        let license = LicenseManager(apiClient: mockClient, storage: defaults, keychainService: testKeychainService)
        trial.startTrial()
        let isReadOnly = trial.isTrialExpired && !license.isActivated
        XCTAssertFalse(isReadOnly)
    }

    func testReadOnlyWhenTrialExpiredAndNotActivated() {
        let startDate = Date()
        let trial = TrialManager(storage: defaults, currentDate: { startDate })
        trial.startTrial()

        let fourDaysLater = Calendar.current.date(byAdding: .day, value: 4, to: startDate)!
        let expiredTrial = TrialManager(storage: defaults, currentDate: { fourDaysLater })
        let license = LicenseManager(apiClient: mockClient, storage: defaults, keychainService: testKeychainService)

        let isReadOnly = expiredTrial.isTrialExpired && !license.isActivated
        XCTAssertTrue(isReadOnly)
    }

    func testNotReadOnlyWhenActivated() async throws {
        let startDate = Date()
        let trial = TrialManager(storage: defaults, currentDate: { startDate })
        trial.startTrial()

        let fourDaysLater = Calendar.current.date(byAdding: .day, value: 4, to: startDate)!
        let expiredTrial = TrialManager(storage: defaults, currentDate: { fourDaysLater })
        let license = LicenseManager(apiClient: mockClient, storage: defaults, keychainService: testKeychainService)
        try await license.activate(key: "VALID")

        let isReadOnly = expiredTrial.isTrialExpired && !license.isActivated
        XCTAssertFalse(isReadOnly)
    }

    func testNotReadOnlyBeforeTrialStarts() {
        let trial = TrialManager(storage: defaults, currentDate: { Date() })
        let license = LicenseManager(apiClient: mockClient, storage: defaults, keychainService: testKeychainService)

        let isReadOnly = trial.isTrialExpired && !license.isActivated
        XCTAssertFalse(isReadOnly)
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `xcodebuild test -project Maestro.xcodeproj -scheme MaestroTests -destination 'platform=macOS' -quiet 2>&1 | tail -10`
Expected: All tests pass

- [ ] **Step 3: Implement AppState**

Create `Maestro/Services/AppState.swift`:

```swift
import Foundation
import MaestroCore

/// Central app state that bridges TrialManager and LicenseManager to SwiftUI.
///
/// Key design: TrialManager and LicenseManager are NOT @Observable (their state
/// comes from UserDefaults/Keychain, so @Observable wouldn't track changes).
/// Instead, AppState mirrors their state into stored properties. Since AppState
/// IS @Observable, SwiftUI views reading these stored properties will re-render
/// when they change. The `refresh()` method syncs from the underlying managers
/// and must be called after every mutation.
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
        trialManager: TrialManager = TrialManager(),
        licenseManager: LicenseManager = LicenseManager()
    ) {
        self.trialManager = trialManager
        self.licenseManager = licenseManager
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

    /// Syncs stored properties from underlying managers.
    /// Must be called after every mutation to TrialManager or LicenseManager.
    func refresh() {
        isTrialStarted = trialManager.isTrialStarted
        isTrialExpired = trialManager.isTrialExpired
        daysRemaining = trialManager.daysRemaining
        isActivated = licenseManager.isActivated
        currentLicenseKey = licenseManager.licenseKey
    }

    /// Hourly refresh to catch trial expiry during a long session
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
```

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild build -project Maestro.xcodeproj -scheme Maestro -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add Maestro/Services/AppState.swift MaestroTests/Services/AppStateTests.swift
git commit -m "feat: add AppState with mirrored stored properties for SwiftUI reactivity"
```

---

## Chunk 2: UI and Integration

### Task 6: First-Launch Onboarding Flow

**Files:**
- Create: `Maestro/Views/Onboarding/OnboardingView.swift`
- Create: `Maestro/Views/Onboarding/APIKeySetupView.swift`

- [ ] **Step 1: Create APIKeySetupView**

Create `Maestro/Views/Onboarding/APIKeySetupView.swift`:

```swift
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
```

- [ ] **Step 2: Create OnboardingView**

Create `Maestro/Views/Onboarding/OnboardingView.swift`:

```swift
import SwiftUI
import MaestroCore

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var currentStep = 0
    @State private var apiKey = ""

    var body: some View {
        VStack(spacing: 0) {
            // Content
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

            // Navigation
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
                            // Store API key in Keychain for later use.
                            // TODO: When spawning Claude CLI, set ANTHROPIC_API_KEY env var
                            // from this stored key in AgentRunner.start(), or configure
                            // Claude CLI to read from this keychain entry.
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
```

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild build -project Maestro.xcodeproj -scheme Maestro -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Maestro/Views/Onboarding/OnboardingView.swift Maestro/Views/Onboarding/APIKeySetupView.swift
git commit -m "feat: add first-launch onboarding with API key setup guide"
```

---

### Task 7: Trial Banner and License Activation Sheet

These two views depend on each other (banner presents the sheet), so they are implemented and committed together.

**Files:**
- Create: `Maestro/Views/Shared/TrialBannerView.swift`
- Create: `Maestro/Views/Shared/LicenseActivationSheet.swift`

- [ ] **Step 1: Create LicenseActivationSheet**

Create `Maestro/Views/Shared/LicenseActivationSheet.swift`:

```swift
import SwiftUI

struct LicenseActivationSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var licenseKey = ""
    @State private var isActivating = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Activate License")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enter the license key from your purchase email.")
                .foregroundStyle(.secondary)

            TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $licenseKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            if let error = appState.licenseError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isActivating {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Activate") {
                    Task {
                        isActivating = true
                        let success = await appState.activateLicense(key: licenseKey.trimmingCharacters(in: .whitespaces))
                        isActivating = false
                        if success {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty || isActivating)
            }

            Divider()

            HStack {
                Text("Don't have a license?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Buy Maestro — $49") {
                    // TODO: Replace with actual Lemon Squeezy store URL
                    if let url = URL(string: "https://maestro.lemonsqueezy.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
```

- [ ] **Step 2: Create TrialBannerView**

Create `Maestro/Views/Shared/TrialBannerView.swift`:

```swift
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
                    // TODO: Replace with actual Lemon Squeezy store URL
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
```

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild build -project Maestro.xcodeproj -scheme Maestro -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Maestro/Views/Shared/TrialBannerView.swift Maestro/Views/Shared/LicenseActivationSheet.swift
git commit -m "feat: add trial banner and license activation UI"
```

---

### Task 8: Read-Only Mode Enforcement

**Files:**
- Modify: `Maestro/Services/AgentOrchestrator.swift`
- Modify: `Maestro/Views/Shared/TaskDetailView.swift`

- [ ] **Step 1: Add AppState dependency to AgentOrchestrator**

In `Maestro/Services/AgentOrchestrator.swift`:

Add property after line 10 (`var defaultMaxConcurrency: Int = 3`):

```swift
    var appState: AppState?
```

Add guard at the start of `runAgent` body (line 27, before `let taskId = task.id`):

```swift
        // Fail-closed: if AppState is not wired, block agent runs as a safety measure.
        // This ensures licensing is never accidentally bypassed.
        guard appState?.canRunAgents == true else {
            print("[Agent] Blocked: license check failed or AppState not configured")
            return
        }
```

Add the same guard at the start of `resumeAgent` body (line 131, before `let taskId = task.id`):

```swift
        guard appState?.canRunAgents == true else {
            print("[Agent] Blocked: license check failed or AppState not configured")
            return
        }
```

- [ ] **Step 2: Disable Run Agent and Resume buttons in TaskDetailView**

In `Maestro/Views/Shared/TaskDetailView.swift`:

Add after line 10 (`@Environment(AgentOrchestrator.self) private var orchestrator`):

```swift
    @Environment(AppState.self) private var appState
```

On the Run Agent button (line 209), replace the existing `.disabled` modifier:

```swift
                            .disabled((task.project?.workspaceRoot.isEmpty ?? true) || appState.isReadOnly)
```

On the Resume button (line 219, after `.buttonStyle(.bordered)`), add:

```swift
                                .disabled(appState.isReadOnly)
```

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild build -project Maestro.xcodeproj -scheme Maestro -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Maestro/Services/AgentOrchestrator.swift Maestro/Views/Shared/TaskDetailView.swift
git commit -m "feat: enforce read-only mode — block agent runs when trial expired"
```

---

### Task 9: License Info in Settings

**Files:**
- Modify: `Maestro/Views/Settings/GeneralSettingsView.swift`

- [ ] **Step 1: Add license section to GeneralSettingsView**

In `Maestro/Views/Settings/GeneralSettingsView.swift`:

Add after line 5 (`@Environment(AgentOrchestrator.self) private var orchestrator`):

```swift
    @Environment(AppState.self) private var appState
    @State private var showingLicenseSheet = false
```

Add a new `Section("License")` inside the Form, before `Section("Claude CLI")` (before line 12):

```swift
            Section("License") {
                HStack {
                    if appState.isActivated {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text("Licensed")
                                .fontWeight(.medium)
                            if let key = appState.currentLicenseKey {
                                Text(maskedKey(key))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Deactivate") {
                            Task { await appState.deactivateLicense() }
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Image(systemName: "key")
                            .foregroundStyle(.secondary)
                        Text(appState.trialStatusText)
                            .foregroundStyle(appState.isReadOnly ? .red : .secondary)
                        Spacer()
                        Button("Activate License") {
                            showingLicenseSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
```

Add after `.formStyle(.grouped)` (line 97), before `.padding()` (line 98):

```swift
        .sheet(isPresented: $showingLicenseSheet) {
            LicenseActivationSheet()
        }
```

Add helper method at the bottom of the struct (before the closing `}`):

```swift
    private func maskedKey(_ key: String) -> String {
        guard key.count > 8 else { return key }
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        return "\(prefix)...\(suffix)"
    }
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -project Maestro.xcodeproj -scheme Maestro -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Maestro/Views/Settings/GeneralSettingsView.swift
git commit -m "feat: add license info and activation to settings"
```

---

### Task 10: Wire AppState into App Lifecycle

**Files:**
- Modify: `Maestro/MaestroApp.swift`
- Modify: `Maestro/Views/ContentView.swift`

- [ ] **Step 1: Update MaestroApp.swift**

Replace the contents of `Maestro/MaestroApp.swift` with:

```swift
import SwiftUI
import SwiftData
import MaestroCore

@main
struct MaestroApp: App {
    let modelContainer: ModelContainer
    @State private var orchestrator = AgentOrchestrator()
    @State private var appState = AppState()

    init() {
        do {
            modelContainer = try MaestroStore.makeContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(orchestrator)
                .environment(appState)
                .task {
                    orchestrator.appState = appState
                    await appState.validateOnLaunch()
                }
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environment(orchestrator)
                .environment(appState)
                .modelContainer(modelContainer)
        }
    }
}
```

- [ ] **Step 2: Update ContentView.swift — add trial banner and onboarding**

In `Maestro/Views/ContentView.swift`, make three targeted changes:

**Change 1:** Add AppState environment. After line 14 (`@Environment(AgentOrchestrator.self) private var orchestrator`), add:

```swift
    @Environment(AppState.self) private var appState
```

**Change 2:** Wrap the `NavigationSplitView` in a `VStack` with the trial banner. Replace line 24 (`NavigationSplitView(columnVisibility: $columnVisibility) {`) with:

```swift
        VStack(spacing: 0) {
            TrialBannerView()

            NavigationSplitView(columnVisibility: $columnVisibility) {
```

And add a closing `}` for the `VStack` after the `NavigationSplitView`'s closing `}` (after line 56, before `.sheet`).

**Change 3:** Add the onboarding sheet. After the `.sheet(isPresented: $showingNewProject)` block (after line 68), add:

```swift
        .sheet(isPresented: Binding(
            get: { appState.isShowingOnboarding },
            set: { appState.isShowingOnboarding = $0 }
        )) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
```

- [ ] **Step 3: Build the full project**

Run: `xcodebuild build -project Maestro.xcodeproj -scheme Maestro -destination 'platform=macOS' -quiet 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 4: Run all tests**

Run: `xcodebuild test -project Maestro.xcodeproj -scheme MaestroTests -destination 'platform=macOS' -quiet 2>&1 | tail -10`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add Maestro/MaestroApp.swift Maestro/Views/ContentView.swift
git commit -m "feat: wire trial, licensing, and onboarding into app lifecycle"
```
