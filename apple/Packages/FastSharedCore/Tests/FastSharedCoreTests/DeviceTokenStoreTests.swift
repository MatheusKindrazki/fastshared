import XCTest
@testable import FastSharedCore

final class DeviceTokenStoreTests: XCTestCase {
    private let storageKey = "fastshared.device-token.v1"

    func test_loadMigratesLegacyDefaultsToKeychainAndDeletesLegacyValue() async throws {
        let defaults = isolatedDefaults()
        let token = DeviceToken(deviceId: UUID(), token: "legacy-token")
        let data = try JSONEncoder().encode(token)
        defaults.set(data, forKey: storageKey)
        let keychain = RecordingKeychain()
        let store = DeviceTokenStore(keychain: keychain, legacyDefaults: defaults)

        let loaded = try await store.load()

        XCTAssertEqual(loaded, token)
        let migrated = try await keychain.read(storageKey)
        XCTAssertEqual(migrated, data)
        XCTAssertNil(defaults.data(forKey: storageKey))
    }

    func test_loadThrowsWhenLegacyMigrationCannotWriteKeychain() async throws {
        let defaults = isolatedDefaults()
        let token = DeviceToken(deviceId: UUID(), token: "legacy-token")
        defaults.set(try JSONEncoder().encode(token), forKey: storageKey)
        let keychain = RecordingKeychain(writeError: StubKeychainError.denied)
        let store = DeviceTokenStore(keychain: keychain, legacyDefaults: defaults)

        do {
            _ = try await store.load()
            XCTFail("expected keychain write failure")
        } catch StubKeychainError.denied {
            XCTAssertNotNil(defaults.data(forKey: storageKey))
        }
    }

    func test_saveWritesKeychainAndClearsLegacyDefaults() async throws {
        let defaults = isolatedDefaults()
        defaults.set(Data([1, 2, 3]), forKey: storageKey)
        let keychain = RecordingKeychain()
        let store = DeviceTokenStore(keychain: keychain, legacyDefaults: defaults)
        let token = DeviceToken(deviceId: UUID(), token: "new-token")

        try await store.save(token)

        let maybeStored = try await keychain.read(storageKey)
        let stored = try XCTUnwrap(maybeStored)
        XCTAssertEqual(try JSONDecoder().decode(DeviceToken.self, from: stored), token)
        XCTAssertNil(defaults.data(forKey: storageKey))
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "dev.kindrazki.fastshared.device-token-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return .standard }
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

private enum StubKeychainError: Error {
    case denied
}

private final class RecordingKeychain: KeychainStoring, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let writeError: Error?

    init(writeError: Error? = nil) {
        self.writeError = writeError
    }

    func read(_ key: String) async throws -> Data? {
        storage[key]
    }

    func write(_ data: Data, for key: String) async throws {
        if let writeError { throw writeError }
        storage[key] = data
    }

    func delete(_ key: String) async throws {
        storage.removeValue(forKey: key)
    }
}
