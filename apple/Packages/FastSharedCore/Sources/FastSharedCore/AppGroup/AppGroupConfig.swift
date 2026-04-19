import Foundation

public enum AppGroupConfig {
    public static let backgroundSessionIdentifier: String = "dev.kindrazki.fastshared.upload"

    public static var identifier: String {
        AppGroupPaths.groupIdentifier
    }

    public static var keychainAccessGroup: String {
        // WHY: the access group must include the team's App Identifier Prefix at runtime; the prefix is
        // folded in automatically by the entitlements `$(AppIdentifierPrefix)` substitution. We expose the
        // unprefixed form here since Security framework handles prefix matching based on entitlement.
        "dev.kindrazki.fastshared"
    }

    public static var apiBaseURL: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let url = URL(string: value) {
            return url
        }
        return URL(string: "https://api.fastshared.app")!
    }

    public static var shortLinkHost: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "SHORT_LINK_HOST") as? String,
           let url = URL(string: value) {
            return url
        }
        return URL(string: "https://fsh.re")!
    }
}
