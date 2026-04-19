import Foundation

public actor DeviceTokenStore {
    private static let keychainKey = "device-token.v1"

    private let keychain: KeychainStoring
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(keychain: KeychainStoring) {
        self.keychain = keychain
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() async throws -> DeviceToken? {
        guard let data = try await keychain.read(Self.keychainKey) else { return nil }
        return try decoder.decode(DeviceToken.self, from: data)
    }

    public func save(_ token: DeviceToken) async throws {
        let data = try encoder.encode(token)
        try await keychain.write(data, for: Self.keychainKey)
    }

    public func clear() async throws {
        try await keychain.delete(Self.keychainKey)
    }
}
