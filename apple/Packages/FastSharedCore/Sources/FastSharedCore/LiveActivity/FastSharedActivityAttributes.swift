import Foundation

// WHY: ActivityKit is importable on macOS but the `ActivityAttributes` protocol itself is
// marked unavailable there. Gate on `os(iOS)` so the type only appears in iOS builds.
#if os(iOS)
import ActivityKit

/// Attributes + content-state shared between the main app, the share extension, and the
/// FastSharedLiveActivity widget extension. Modeling a single upload's lifecycle on the
/// Dynamic Island and Lock Screen.
public struct FastSharedActivityAttributes: ActivityAttributes, Sendable, Hashable {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Phase: String, Codable, Sendable, Hashable {
            case uploading
            case completed
            case failed
        }

        public var phase: Phase
        public var progress: Double
        public var bytesSent: Int64
        public var bytesTotal: Int64
        public var shortUrl: String?
        public var expiresAt: Date?
        public var errorReason: String?

        public init(phase: Phase,
                    progress: Double,
                    bytesSent: Int64,
                    bytesTotal: Int64,
                    shortUrl: String? = nil,
                    expiresAt: Date? = nil,
                    errorReason: String? = nil) {
            self.phase = phase
            self.progress = progress
            self.bytesSent = bytesSent
            self.bytesTotal = bytesTotal
            self.shortUrl = shortUrl
            self.expiresAt = expiresAt
            self.errorReason = errorReason
        }
    }

    public let clientJobId: UUID
    public let filename: String
    public let contentType: String
    public let retentionPolicy: String

    public init(clientJobId: UUID,
                filename: String,
                contentType: String,
                retentionPolicy: String) {
        self.clientJobId = clientJobId
        self.filename = filename
        self.contentType = contentType
        self.retentionPolicy = retentionPolicy
    }
}

public extension FastSharedActivityAttributes {
    /// Convenience for the retention badge ("1h" / "24h" / "7d" / "30d").
    var retentionBadge: String {
        switch retentionPolicy {
        case RetentionPolicy.oneHour.rawValue: return "1h"
        case RetentionPolicy.oneDay.rawValue: return "24h"
        case RetentionPolicy.oneWeek.rawValue: return "7d"
        case RetentionPolicy.oneMonth.rawValue: return "30d"
        default: return retentionPolicy
        }
    }
}
#endif
