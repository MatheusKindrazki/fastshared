import Foundation

/// Why the paywall appeared.
///
/// Drives the hero line of `PaywallView` and feeds analytics. `id` is derived
/// from the case discriminant so SwiftUI's `.sheet(item:)` binding treats each
/// distinct presentation as a fresh sheet.
public enum PaywallTriggerContext: Sendable, Identifiable, Equatable {
    case dailyCapReached(used: Int, cap: Int)
    case cloudSyncRequested
    case longRetentionRequested(policy: RetentionPolicy)
    case largeFileRequested(sizeBytes: Int64)
    case serverForced(errorCode: String)

    public var id: String {
        switch self {
        case .dailyCapReached(let used, let cap): return "daily-\(used)-\(cap)"
        case .cloudSyncRequested: return "cloud-sync"
        case .longRetentionRequested(let p): return "retention-\(p.rawValue)"
        case .largeFileRequested(let n): return "size-\(n)"
        case .serverForced(let code): return "server-\(code)"
        }
    }

    /// Analytics-friendly stable discriminator.
    public var analyticsSlug: String {
        switch self {
        case .dailyCapReached: return "daily_cap"
        case .cloudSyncRequested: return "cloud_sync"
        case .longRetentionRequested: return "long_retention"
        case .largeFileRequested: return "large_file"
        case .serverForced: return "server_forced"
        }
    }
}
