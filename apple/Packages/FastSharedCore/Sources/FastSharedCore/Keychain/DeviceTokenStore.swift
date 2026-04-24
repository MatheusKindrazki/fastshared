import Foundation

public actor DeviceTokenStore {
    private static let storageKey = "fastshared.device-token.v1"

    private let keychain: KeychainStoring
    private let legacyDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(keychain: KeychainStoring = KeychainStore(
        service: AppGroupConfig.identifier,
        accessGroup: AppGroupConfig.keychainAccessGroup
    ), legacyDefaults: UserDefaults? = nil) {
        self.keychain = keychain
        self.legacyDefaults = legacyDefaults
            ?? UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
            ?? .standard
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() async throws -> DeviceToken? {
        if let data = try await keychain.read(Self.storageKey) {
            return try decoder.decode(DeviceToken.self, from: data)
        }

        guard let legacyData = legacyDefaults.data(forKey: Self.storageKey) else { return nil }
        let token = try decoder.decode(DeviceToken.self, from: legacyData)
        try await keychain.write(legacyData, for: Self.storageKey)
        legacyDefaults.removeObject(forKey: Self.storageKey)
        return token
    }

    public func save(_ token: DeviceToken) async throws {
        let data = try encoder.encode(token)
        try await keychain.write(data, for: Self.storageKey)
        legacyDefaults.removeObject(forKey: Self.storageKey)
    }

    public func clear() async throws {
        try await keychain.delete(Self.storageKey)
        legacyDefaults.removeObject(forKey: Self.storageKey)
    }
}
