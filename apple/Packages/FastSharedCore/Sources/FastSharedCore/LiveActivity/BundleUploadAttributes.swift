import Foundation

// WHY: same iOS-only gate as FastSharedActivityAttributes — ActivityKit's
// `ActivityAttributes` protocol is unavailable on macOS even though the module
// is importable.
#if os(iOS)
import ActivityKit

/// Attributes + content-state for the *bundle* upload Live Activity.
///
/// Single uploads keep `FastSharedActivityAttributes`; bundles use this so the
/// widget can show an aggregated headline ("Sending N files · X%") and a list
/// of filenames without inflating the per-job attributes used everywhere else.
public struct BundleUploadAttributes: ActivityAttributes, Sendable, Hashable {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Phase: String, Codable, Sendable, Hashable {
            case uploading
            case completed
            case failed
        }

        public var phase: Phase
        public var bytesUploaded: Int64
        public var progress: Double            // redundant with bytes/total — eases widget math
        public var bundleShortUrl: String?
        public var expiresAt: Date?
        public var errorReason: String?

        public init(phase: Phase,
                    bytesUploaded: Int64,
                    progress: Double,
                    bundleShortUrl: String? = nil,
                    expiresAt: Date? = nil,
                    errorReason: String? = nil) {
            self.phase = phase
            self.bytesUploaded = bytesUploaded
            self.progress = progress
            self.bundleShortUrl = bundleShortUrl
            self.expiresAt = expiresAt
            self.errorReason = errorReason
        }
    }

    /// Stable bundle identifier (matches backend `bundleToken`). Used as the
    /// activity key so cross-process resolution can find the right Activity.
    public let bundleToken: String
    public let fileCount: Int
    public let totalBytes: Int64
    /// Top-N filenames for the expanded Dynamic Island list. Capped client-side
    /// to keep the activity payload small (Apple enforces ~4 KB).
    public let filenames: [String]
    public let retentionPolicy: String

    public init(bundleToken: String,
                fileCount: Int,
                totalBytes: Int64,
                filenames: [String],
                retentionPolicy: String) {
        self.bundleToken = bundleToken
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.filenames = filenames
        self.retentionPolicy = retentionPolicy
    }
}

public extension BundleUploadAttributes {
    /// Mirror of `FastSharedActivityAttributes.retentionBadge` so the widget
    /// can use the same pill component without branching on attribute type.
    var retentionBadge: String {
        switch retentionPolicy {
        case RetentionPolicy.oneMinute.rawValue: return "60s"
        case RetentionPolicy.oneHour.rawValue: return "1h"
        case RetentionPolicy.oneDay.rawValue: return "24h"
        case RetentionPolicy.oneWeek.rawValue: return "7d"
        case RetentionPolicy.oneMonth.rawValue: return "30d"
        default: return retentionPolicy
        }
    }
}
#endif
