import Foundation

/// Shared App-Group `UserDefaults` keys for user preferences that BOTH the app
/// UI and the Core layer need to read. Keeping them here (rather than as private
/// string literals in SettingsView) lets the upload pipeline honor the same
/// preference the user toggles in Settings.
public enum SettingsKeys {
    /// Bool. When true (default), the short link is copied to the clipboard
    /// automatically the moment a share is ready. When false, the user copies
    /// manually from the history row. Read by `UploadOrchestrator`.
    public static let copyLinkAuto = "copy_link_auto_v1"
    /// Bool. When true (default), newly-created share links request a push
    /// notification the first time the recipient opens the link.
    public static let notifyOnOpen = "notify_on_open_v1"
    /// Legacy beta key used by the first share-extension UI. Read once so the
    /// preference survives the migration to the versioned key.
    public static let legacyNotifyOnOpen = "notify_on_open"
    /// Last APNs token received from iOS, cached so onboarding/sign-in can
    /// rebind it to the current backend device token.
    public static let cachedAPNSToken = "cached_apns_token_v1"
    public static let cachedAPNSEnvironment = "cached_apns_environment_v1"
}

/// Convenience reader for Core-side code (the orchestrator) so it doesn't
/// re-derive the suite name at each call site.
public enum SettingsPreferences {
    public static func copyLinkAutoEnabled() -> Bool {
        let defaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
        // Absent key → default ON (preserves the historical always-copy UX).
        return defaults?.object(forKey: SettingsKeys.copyLinkAuto) as? Bool ?? true
    }

    public static func notifyOnOpenEnabled() -> Bool {
        let defaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
        if let value = defaults?.object(forKey: SettingsKeys.notifyOnOpen) as? Bool {
            return value
        }
        if let legacy = defaults?.object(forKey: SettingsKeys.legacyNotifyOnOpen) as? Bool {
            defaults?.set(legacy, forKey: SettingsKeys.notifyOnOpen)
            return legacy
        }
        return true
    }

    public static func setNotifyOnOpenEnabled(_ enabled: Bool) {
        let defaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
        defaults?.set(enabled, forKey: SettingsKeys.notifyOnOpen)
    }
}
