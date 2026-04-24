import Foundation

public enum AppGroupConfig {
    public static let backgroundSessionIdentifier: String = "dev.kindrazki.fastshared.upload"

    public static var identifier: String {
        AppGroupPaths.groupIdentifier
    }

    public static var keychainAccessGroup: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "KEYCHAIN_ACCESS_GROUP") as? String,
           !value.isEmpty, !value.contains("$(") {
            return value
        }
        // SwiftPM tests and unsigned local utilities do not receive the
        // expanded AppIdentifierPrefix. Empty means "do not set an access
        // group" and avoids errSecMissingEntitlement outside signed app builds.
        return ""
    }

    // WHY: Info.plist keys stay supported for future override, but the default
    // is the real deployed host so a misconfigured xcconfig doesn't silently
    // hit a non-existent domain. Flip when we have a separate dev environment.
    public static var apiBaseURL: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !value.isEmpty, !value.contains("$("),
           let url = URL(string: value) {
            return url
        }
        return URL(string: "https://api.fastsha.red")!
    }

    public static var shortLinkHost: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "SHORT_LINK_HOST") as? String,
           !value.isEmpty, !value.contains("$("),
           let url = URL(string: value) {
            return url
        }
        return URL(string: "https://fastsha.red")!
    }
}
