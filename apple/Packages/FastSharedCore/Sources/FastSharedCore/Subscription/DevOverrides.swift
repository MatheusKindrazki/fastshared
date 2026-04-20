import Foundation

/// Developer-only overrides for subscription gating. Reads from the shared App
/// Group defaults so the main app and share extension agree on the flag.
///
/// In DEBUG builds the flag defaults to **true** (all Free-tier caps skipped)
/// so internal testing isn't blocked by the daily limit. In Release the flag
/// is always hard-coded to **false** — production users get real gating.
///
/// To flip it during testing, toggle `SettingsView`'s "Developer → Unlimited
/// free uploads" switch, or set `dev_unlimited_free_caps` in the App Group
/// UserDefaults manually.
public enum DevOverrides {
    public static let unlimitedFreeCapsKey = "dev_unlimited_free_caps"

    /// True when the daily-cap / file-size / retention gate should be bypassed.
    ///
    /// - DEBUG: returns the UserDefaults bool (defaults to `true` when unset).
    /// - Release: always `false`. The binary never ships with a bypass path.
    public static var unlimitedFreeCaps: Bool {
        #if DEBUG
        let defaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier) ?? .standard
        if defaults.object(forKey: unlimitedFreeCapsKey) == nil {
            return true
        }
        return defaults.bool(forKey: unlimitedFreeCapsKey)
        #else
        return false
        #endif
    }

    /// Sets the flag in App Group defaults (DEBUG only — no-op in Release).
    public static func setUnlimitedFreeCaps(_ value: Bool) {
        #if DEBUG
        let defaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier) ?? .standard
        defaults.set(value, forKey: unlimitedFreeCapsKey)
        #endif
    }
}
