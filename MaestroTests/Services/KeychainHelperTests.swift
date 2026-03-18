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
