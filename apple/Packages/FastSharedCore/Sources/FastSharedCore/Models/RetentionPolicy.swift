import Foundation

public enum RetentionPolicy: String, CaseIterable, Sendable, Codable {
    case oneHour
    case oneDay
    case oneWeek
    case oneMonth
    case custom

    public var ttlSeconds: TimeInterval {
        switch self {
        case .oneHour: return 3600
        case .oneDay: return 86_400
        case .oneWeek: return 604_800
        case .oneMonth: return 2_592_000
        case .custom: return .nan
        }
    }

    public var displayName: String {
        switch self {
        case .oneHour: return "1 hour"
        case .oneDay: return "1 day"
        case .oneWeek: return "1 week"
        case .oneMonth: return "1 month"
        case .custom: return "Custom"
        }
    }

    public static let `default`: RetentionPolicy = .oneDay

    // WHY: .custom is intentionally excluded from the share extension picker in MVP; power users
    // can come later via a settings-level override.
    public static let shareable: [RetentionPolicy] = [.oneHour, .oneDay, .oneWeek, .oneMonth]

    /// Reads the user's preferred retention from the shared App Group suite, falling back to `.default`.
    /// Used by surfaces that run outside the SwiftUI environment (App Intents, headless entry points).
    public static func defaultFromAppGroup() -> RetentionPolicy {
        let defaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
        if let raw = defaults?.string(forKey: "default_retention_policy"),
           let policy = RetentionPolicy(rawValue: raw) {
            return policy
        }
        return .default
    }
}
