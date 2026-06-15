import Foundation
import OSLog

public enum DeviceRegistration {
    public static func ensureDeviceToken(apiClient: APIClientProtocol,
                                         tokenStore: DeviceTokenStore) async throws -> DeviceToken {
        if let existing = try await tokenStore.load() { return existing }
        let token = try await apiClient.registerDevice(platform: currentPlatform,
                                                       appVersion: currentAppVersion)
        try await tokenStore.save(token)
        return token
    }

    public static var currentPlatform: String {
        #if os(iOS)
        return "ios"
        #elseif os(macOS)
        return "macos"
        #else
        return "unknown"
        #endif
    }

    public static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}

public enum PushNotificationRegistrar {
    private static let log = Logger(subsystem: Log.subsystem, category: "push")

    public static func registerAPNSToken(_ apnsToken: String,
                                         environment: String,
                                         apiClient: APIClientProtocol? = nil,
                                         tokenStore: DeviceTokenStore? = nil) async {
        cache(apnsToken: apnsToken, environment: environment)
        await syncCachedAPNSToken(apiClient: apiClient, tokenStore: tokenStore)
    }

    public static func syncCachedAPNSToken(apiClient: APIClientProtocol? = nil,
                                           tokenStore: DeviceTokenStore? = nil) async {
        let defaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
        guard let apnsToken = defaults?.string(forKey: SettingsKeys.cachedAPNSToken),
              !apnsToken.isEmpty else { return }
        let environment = defaults?.string(forKey: SettingsKeys.cachedAPNSEnvironment) ?? "production"
        let keychain = KeychainStore(service: AppGroupConfig.identifier,
                                     accessGroup: AppGroupConfig.keychainAccessGroup)
        let resolvedTokenStore = tokenStore ?? DeviceTokenStore(keychain: keychain)
        let resolvedAPIClient = apiClient ?? APIClient(tokenStore: resolvedTokenStore)
        do {
            _ = try await DeviceRegistration.ensureDeviceToken(apiClient: resolvedAPIClient,
                                                               tokenStore: resolvedTokenStore)
            try await resolvedAPIClient.updatePushToken(apnsToken: apnsToken, environment: environment)
        } catch {
            log.error("APNs token sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func cache(apnsToken: String, environment: String) {
        let defaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
        defaults?.set(apnsToken, forKey: SettingsKeys.cachedAPNSToken)
        defaults?.set(environment, forKey: SettingsKeys.cachedAPNSEnvironment)
    }
}
