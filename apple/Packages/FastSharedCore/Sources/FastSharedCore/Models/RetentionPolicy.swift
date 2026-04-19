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
}
