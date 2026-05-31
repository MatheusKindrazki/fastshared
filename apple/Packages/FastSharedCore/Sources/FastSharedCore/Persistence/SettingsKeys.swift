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
}

/// Convenience reader for Core-side code (the orchestrator) so it doesn't
/// re-derive the suite name at each call site.
public enum SettingsPreferences {
    public static func copyLinkAutoEnabled() -> Bool {
        let defaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
        // Absent key → default ON (preserves the historical always-copy UX).
        return defaults?.object(forKey: SettingsKeys.copyLinkAuto) as? Bool ?? true
    }
}
