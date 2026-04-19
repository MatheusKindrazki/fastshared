import Foundation

// WHY: the device token is a server-revocable bearer, not a secret that needs
// Secure Enclave treatment. Storing it in the App Group UserDefaults (already
// configured) lets the main app and the share extension read/write it without
// requiring the Keychain Sharing capability on the ShareExt App ID — a setup
// step that's easy to miss in the Apple Developer portal and produces
// errSecMissingEntitlement (-34018) when absent. If a future feature needs
// to protect an actual password, reach for `KeychainStore` directly.
public actor DeviceTokenStore {
    private static let storageKey = "fastshared.device-token.v1"

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
            ?? .standard
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // WHY: keeping the legacy initializer so existing call sites that still
    // pass a KeychainStore keep compiling; the keychain argument is ignored.
    public init(keychain: KeychainStoring) {
        self.init(defaults: nil)
    }

    public func load() async throws -> DeviceToken? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        return try decoder.decode(DeviceToken.self, from: data)
    }

    public func save(_ token: DeviceToken) async throws {
        let data = try encoder.encode(token)
        defaults.set(data, forKey: Self.storageKey)
    }

    public func clear() async throws {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
