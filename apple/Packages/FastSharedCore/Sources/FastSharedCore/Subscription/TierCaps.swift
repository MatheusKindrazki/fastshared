import Foundation

/// Per-tier hard caps applied across the client. Server may override these via `/v1/me`.
///
/// `dailyUploadLimit == nil` means unlimited; render as `∞` in UI.
public struct TierCaps: Sendable, Codable, Equatable {
    public let dailyUploadLimit: Int?
    public let maxFileSizeBytes: Int64
    public let maxRetentionSeconds: TimeInterval
    public let allowsCloudSync: Bool

    public init(dailyUploadLimit: Int?,
                maxFileSizeBytes: Int64,
                maxRetentionSeconds: TimeInterval,
                allowsCloudSync: Bool) {
        self.dailyUploadLimit = dailyUploadLimit
        self.maxFileSizeBytes = maxFileSizeBytes
        self.maxRetentionSeconds = maxRetentionSeconds
        self.allowsCloudSync = allowsCloudSync
    }

    /// ⚠️ TEMPORARY OVERRIDE — 2026-04-20
    /// Mirror of `.pro` while Apple's Paid Apps Agreement is pending: W-8BEN +
    /// BR tax form + bank account. StoreKit returns 0 products in that state,
    /// so TestFlight users can't unlock Pro via purchase. Clamping every gate
    /// open lets the beta run without paywall whiplash. Revert to the canonical
    /// Free tier (3 / 100 MB / 24h / false) as soon as `/v1/me` reports real
    /// subscriptions again.
    public static let free = TierCaps(
        dailyUploadLimit: nil,
        maxFileSizeBytes: 5 * 1024 * 1024 * 1024,
        maxRetentionSeconds: 2_592_000,
        allowsCloudSync: true
    )

    /// Pro tier defaults — unlimited uploads, 5 GB per file, 30 days retention, sync allowed.
    public static let pro = TierCaps(
        dailyUploadLimit: nil,
        maxFileSizeBytes: 5 * 1024 * 1024 * 1024,
        maxRetentionSeconds: 2_592_000,
        allowsCloudSync: true
    )
}

/// Unified tier discriminant carrying the Pro SKU when applicable.
public enum Tier: Sendable, Equatable {
    case free
    case pro(ProTier)

    public var caps: TierCaps {
        switch self {
        case .free: return .free
        case .pro:  return .pro
        }
    }

    public var isPro: Bool {
        if case .pro = self { return true }
        return false
    }
}
