import Foundation

/// Payload the share extension leaves in the App Group for the main app to
/// pick up and actually enqueue.
///
/// Why this exists: `Activity.request` needs the widget descriptors, which
/// are only registered with the main app's process. If the share ext calls
/// `enqueue` directly, the Live Activity is created in the extension and the
/// system can't find a descriptor to render — the Dynamic Island stays empty.
/// The share ext instead parks the request here, opens the main app via the
/// `fastshared://pending-upload` URL scheme, then dismisses. The main app
/// reads the queue in `onOpenURL` and calls `enqueue` from its own process.
public struct PendingShareUpload: Codable, Sendable, Equatable {
    public let id: UUID
    /// Absolute path to the staged file. Both processes see the App Group
    /// container at the same mount point, so absolute works cross-process.
    public let stagedURL: URL
    public let contentType: String
    public let originalFilename: String
    public let sizeBytes: Int64
    public let retentionPolicyRaw: String
    /// Milliseconds since 1970 — avoids Date codable-JSON pitfalls between
    /// the extension and host build versions.
    public let queuedAtMs: Int64

    public init(id: UUID = UUID(),
                stagedURL: URL,
                contentType: String,
                originalFilename: String,
                sizeBytes: Int64,
                retentionPolicyRaw: String,
                queuedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.id = id
        self.stagedURL = stagedURL
        self.contentType = contentType
        self.originalFilename = originalFilename
        self.sizeBytes = sizeBytes
        self.retentionPolicyRaw = retentionPolicyRaw
        self.queuedAtMs = queuedAtMs
    }
}

/// App Group-backed queue the share extension writes to and the main app
/// drains. Atomic-ish by virtue of UserDefaults' read-merge-write on a
/// single key — callers should treat appends and drains as whole-queue
/// operations (read → mutate → write) to minimize the short-lived race
/// window (which at worst drops a redundant duplicate).
public enum PendingShareUploadQueue {
    public static let storageKey = "pending_share_uploads_v1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
    }

    public static func append(_ upload: PendingShareUpload) {
        guard let defaults else { return }
        var current = loadAll()
        current.append(upload)
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: storageKey)
        }
    }

    public static func loadAll() -> [PendingShareUpload] {
        guard let defaults,
              let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PendingShareUpload].self, from: data)
        else { return [] }
        return decoded
    }

    public static func clearAll() {
        defaults?.removeObject(forKey: storageKey)
    }

    /// Reads everything, wipes the queue, returns the snapshot. Main app
    /// uses this on `onOpenURL` / cold launch to drain atomically.
    public static func drain() -> [PendingShareUpload] {
        let all = loadAll()
        clearAll()
        return all
    }
}
