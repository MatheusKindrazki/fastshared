import Foundation
import SwiftData

@Model
public final class UploadJobEntity {
    @Attribute(.unique) public var clientJobId: UUID
    public var statusRaw: String
    public var progress: Double
    public var attemptCount: Int
    public var contentType: String
    public var sizeBytes: Int64
    public var sha256: String?
    public var originalFilename: String?
    public var remoteUploadId: String?
    public var remoteAssetId: String?
    public var shortURLString: String?
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var stagedRelativePath: String
    public var retentionPolicy: String
    public var expiresAt: Date?
    public var deleteAfter: Date?
    // Tier 1: persisted so the "don't re-copy at /complete" guard survives
    // crashes between presign copy and task completion.
    public var linkAlreadyCopied: Bool = false

    public init(clientJobId: UUID,
                status: UploadJobStatus,
                progress: Double = 0,
                attemptCount: Int = 0,
                contentType: String,
                sizeBytes: Int64,
                sha256: String? = nil,
                originalFilename: String? = nil,
                remoteUploadId: String? = nil,
                remoteAssetId: String? = nil,
                shortURLString: String? = nil,
                errorMessage: String? = nil,
                createdAt: Date = Date(),
                updatedAt: Date = Date(),
                stagedRelativePath: String,
                retentionPolicy: String = RetentionPolicy.default.rawValue,
                expiresAt: Date? = nil,
                deleteAfter: Date? = nil,
                linkAlreadyCopied: Bool = false) {
        self.clientJobId = clientJobId
        self.statusRaw = status.rawValue
        self.progress = progress
        self.attemptCount = attemptCount
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.originalFilename = originalFilename
        self.remoteUploadId = remoteUploadId
        self.remoteAssetId = remoteAssetId
        self.shortURLString = shortURLString
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.stagedRelativePath = stagedRelativePath
        self.retentionPolicy = retentionPolicy
        self.expiresAt = expiresAt
        self.deleteAfter = deleteAfter
        self.linkAlreadyCopied = linkAlreadyCopied
    }

    public var status: UploadJobStatus {
        get { UploadJobStatus(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }

    public func snapshot() -> UploadJob {
        UploadJob(clientJobId: clientJobId,
                  status: status,
                  progress: progress,
                  attemptCount: attemptCount,
                  contentType: contentType,
                  sizeBytes: sizeBytes,
                  sha256: sha256,
                  originalFilename: originalFilename,
                  remoteUploadId: remoteUploadId,
                  remoteAssetId: remoteAssetId,
                  shortURL: shortURLString.flatMap(URL.init(string:)),
                  errorMessage: errorMessage,
                  createdAt: createdAt,
                  updatedAt: updatedAt,
                  stagedRelativePath: stagedRelativePath,
                  retentionPolicy: RetentionPolicy(rawValue: retentionPolicy) ?? .default,
                  expiresAt: expiresAt,
                  deleteAfter: deleteAfter,
                  linkAlreadyCopied: linkAlreadyCopied)
    }
}

@Model
public final class ShareLinkEntity {
    @Attribute(.unique) public var token: String
    // Bundle links carry no canonical asset (junction table holds N children).
    // We keep this non-optional to avoid a SwiftData migration churn across
    // call sites; bundle rows store `bundleSentinelAssetId` (all-zero UUID)
    // and bundledAssets carries the real per-file rows.
    public var assetId: UUID
    public var shortURLString: String
    public var createdAt: Date
    public var visibilityRaw: String
    public var expiresAt: Date
    public var deleteAfter: Date
    public var linkStatus: String
    public var retentionPolicy: String
    public var revokedAt: Date?
    public var lastAccessedAt: Date?
    public var accessCount: Int64
    public var contentType: String
    public var sizeBytes: Int64
    public var originalFilename: String?
    public var isFavorited: Bool
    // M3: bundle support. Defaults preserve existing single-link rows on
    // SwiftData lightweight migration (new prop with default → no-op upgrade).
    public var isBundle: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \BundledAssetEntity.shareLink)
    public var bundledAssets: [BundledAssetEntity] = []

    public init(token: String,
                assetId: UUID,
                shortURLString: String,
                createdAt: Date,
                visibility: Visibility,
                expiresAt: Date,
                deleteAfter: Date,
                linkStatus: String = "active",
                retentionPolicy: String,
                revokedAt: Date? = nil,
                lastAccessedAt: Date? = nil,
                accessCount: Int64 = 0,
                contentType: String,
                sizeBytes: Int64,
                originalFilename: String?,
                isFavorited: Bool = false,
                isBundle: Bool = false,
                bundledAssets: [BundledAssetEntity] = []) {
        self.token = token
        self.assetId = assetId
        self.shortURLString = shortURLString
        self.createdAt = createdAt
        self.visibilityRaw = visibility.rawValue
        self.expiresAt = expiresAt
        self.deleteAfter = deleteAfter
        self.linkStatus = linkStatus
        self.retentionPolicy = retentionPolicy
        self.revokedAt = revokedAt
        self.lastAccessedAt = lastAccessedAt
        self.accessCount = accessCount
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.originalFilename = originalFilename
        self.isFavorited = isFavorited
        self.isBundle = isBundle
        self.bundledAssets = bundledAssets
    }

    public var visibility: Visibility {
        get { Visibility(rawValue: visibilityRaw) ?? .unlisted }
        set { visibilityRaw = newValue.rawValue }
    }

    public var shortURL: URL {
        URL(string: shortURLString) ?? URL(fileURLWithPath: "/")
    }

    public var status: LinkStatus {
        get { LinkStatus(rawValue: linkStatus) ?? .active }
        set { linkStatus = newValue.rawValue }
    }

    public var retention: RetentionPolicy {
        RetentionPolicy(rawValue: retentionPolicy) ?? .default
    }
}

public extension ShareLinkEntity {
    /// Sentinel UUID for bundle rows where there is no canonical single asset.
    /// All-zero UUID is impossible to collide with a real asset id from
    /// `gen_random_uuid()`. UI/sync layers must skip row resolution when the
    /// link reports `isBundle == true` and read `bundledAssets` instead.
    static let bundleSentinelAssetId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}

/// Per-asset row inside a bundled `ShareLinkEntity`. Mirrors the backend
/// `bundle_asset` junction (asset metadata is denormalized so the iOS
/// history list can render without a /b/{token} fetch).
@Model
public final class BundledAssetEntity {
    public var assetId: UUID
    public var filename: String
    public var sizeBytes: Int64
    public var contentType: String
    public var displayOrder: Int
    public var shareLink: ShareLinkEntity?

    public init(assetId: UUID,
                filename: String,
                sizeBytes: Int64,
                contentType: String,
                displayOrder: Int,
                shareLink: ShareLinkEntity? = nil) {
        self.assetId = assetId
        self.filename = filename
        self.sizeBytes = sizeBytes
        self.contentType = contentType
        self.displayOrder = displayOrder
        self.shareLink = shareLink
    }
}

/// One row per device the user has on this iCloud account. Synced via CloudKit
/// (`DeviceRecord`) so the sidebar can list iPhone/iPad/Mac. All properties have
/// defaults — a hard requirement for CloudKit-backed SwiftData models.
@Model
public final class DeviceEntity {
    @Attribute(.unique) public var deviceId: UUID = UUID()
    public var name: String = ""
    /// "iphone" | "ipad" | "mac" — drives the sidebar SF Symbol.
    public var platform: String = ""
    public var lastSeenAt: Date = Date.distantPast
    public var appVersion: String = ""

    public init(deviceId: UUID,
                name: String = "",
                platform: String = "",
                lastSeenAt: Date = .distantPast,
                appVersion: String = "") {
        self.deviceId = deviceId
        self.name = name
        self.platform = platform
        self.lastSeenAt = lastSeenAt
        self.appVersion = appVersion
    }
}

public actor SwiftDataStore {
    public static let shared: SwiftDataStore = {
        do {
            return try SwiftDataStore()
        } catch {
            // WHY: if the shared group container is missing we still want the app to boot with an in-memory store
            // so developers get a usable error path; this keeps SwiftUI previews and unit tests working.
            return SwiftDataStore.inMemoryFallback()
        }
    }()

    public nonisolated let modelContainer: ModelContainer

    public init() throws {
        let schema = Schema([UploadJobEntity.self, ShareLinkEntity.self, BundledAssetEntity.self, DeviceEntity.self])
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupPaths.groupIdentifier) != nil else {
            throw AppGroupError.missingContainer(AppGroupPaths.groupIdentifier)
        }
        let configuration = ModelConfiguration(
            "FastShared",
            schema: schema,
            groupContainer: .identifier(AppGroupPaths.groupIdentifier),
            cloudKitDatabase: .none
        )
        self.modelContainer = try ModelContainer(for: schema, configurations: configuration)
    }

    public init(inMemory: Bool) {
        let schema = Schema([UploadJobEntity.self, ShareLinkEntity.self, BundledAssetEntity.self, DeviceEntity.self])
        let configuration = ModelConfiguration("FastShared", schema: schema, isStoredInMemoryOnly: true)
        self.modelContainer = (try? ModelContainer(for: schema, configurations: configuration)) ?? {
            fatalError("Unable to create in-memory SwiftData container")
        }()
    }

    private static func inMemoryFallback() -> SwiftDataStore {
        SwiftDataStore(inMemory: true)
    }

    @MainActor
    public func mainContext() -> ModelContext {
        modelContainer.mainContext
    }

    public nonisolated func backgroundContext() -> ModelContext {
        ModelContext(modelContainer)
    }
}
