import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

public enum APIEndpoint: Sendable {
    case registerDevice
    case requestUpload
    case completeUpload(uploadId: String)
    case failUpload(uploadId: String)
    case fetchHistory
    case deleteAsset(id: UUID)
    case revokeLink(token: String)

    public var path: String {
        switch self {
        case .registerDevice: return "/v1/devices"
        case .requestUpload: return "/v1/uploads"
        case .completeUpload(let id): return "/v1/uploads/\(id)/complete"
        case .failUpload(let id): return "/v1/uploads/\(id)/fail"
        case .fetchHistory: return "/v1/history"
        case .deleteAsset(let id): return "/v1/assets/\(id.uuidString)"
        case .revokeLink(let token): return "/v1/links/\(token)/revoke"
        }
    }

    public var method: HTTPMethod {
        switch self {
        case .registerDevice, .requestUpload, .completeUpload, .failUpload, .revokeLink: return .post
        case .fetchHistory: return .get
        case .deleteAsset: return .delete
        }
    }
}

public struct RegisterDeviceRequest: Sendable, Codable, Equatable {
    public let platform: String
    public let appVersion: String

    public init(platform: String, appVersion: String) {
        self.platform = platform
        self.appVersion = appVersion
    }
}

public struct RegisterDeviceResponse: Sendable, Codable, Equatable {
    // WHY: backend emits "deviceToken" (not "token") in POST /v1/devices to make the
    // registration payload self-documenting when it sits alongside a deviceId.
    public let deviceId: UUID
    public let deviceToken: String

    public init(deviceId: UUID, deviceToken: String) {
        self.deviceId = deviceId
        self.deviceToken = deviceToken
    }
}

public struct DedupeInfo: Sendable, Codable, Equatable {
    public let assetId: UUID
    public let shortUrl: URL
    public let token: String
    public let expiresAt: Date
    public let deleteAfter: Date
    public let retentionPolicy: String

    public init(assetId: UUID,
                shortUrl: URL,
                token: String,
                expiresAt: Date,
                deleteAfter: Date,
                retentionPolicy: String) {
        self.assetId = assetId
        self.shortUrl = shortUrl
        self.token = token
        self.expiresAt = expiresAt
        self.deleteAfter = deleteAfter
        self.retentionPolicy = retentionPolicy
    }
}

public struct PresignRequest: Sendable, Codable, Equatable {
    public let clientJobId: UUID
    public let contentType: String
    public let sizeBytes: Int64
    public let sha256: String?
    public let originalFilename: String?
    public let retentionPolicy: String
    public let customTtlSeconds: Int?

    public init(clientJobId: UUID,
                contentType: String,
                sizeBytes: Int64,
                sha256: String?,
                originalFilename: String?,
                retentionPolicy: String,
                customTtlSeconds: Int? = nil) {
        self.clientJobId = clientJobId
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.originalFilename = originalFilename
        self.retentionPolicy = retentionPolicy
        self.customTtlSeconds = customTtlSeconds
    }
}

public struct UploadInstruction: Sendable, Codable, Equatable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let expiresAt: Date

    public init(url: URL,
                method: String,
                headers: [String: String],
                expiresAt: Date) {
        self.url = url
        self.method = method
        self.headers = headers
        self.expiresAt = expiresAt
    }
}

// WHY: the backend returns two disjoint shapes on the same endpoint.
// Happy path carries uploadId + upload + retention metadata; the dedup path
// returns ONLY `deduped` with the existing share-link fields. Every field
// outside of `deduped` is therefore optional so both responses decode cleanly.
public struct PresignResponse: Sendable, Codable, Equatable {
    public let uploadId: String?
    public let bucket: String?
    public let storageKey: String?
    public let contentType: String?
    public let sizeBytes: Int64?
    public let upload: UploadInstruction?
    public let retentionPolicy: String?
    public let expiresAt: Date?
    public let deleteAfter: Date?
    public let deduped: DedupeInfo?

    public init(uploadId: String?,
                bucket: String?,
                storageKey: String?,
                contentType: String?,
                sizeBytes: Int64?,
                upload: UploadInstruction?,
                retentionPolicy: String?,
                expiresAt: Date?,
                deleteAfter: Date?,
                deduped: DedupeInfo?) {
        self.uploadId = uploadId
        self.bucket = bucket
        self.storageKey = storageKey
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.upload = upload
        self.retentionPolicy = retentionPolicy
        self.expiresAt = expiresAt
        self.deleteAfter = deleteAfter
        self.deduped = deduped
    }
}

public struct CompleteRequest: Sendable, Codable, Equatable {
    public let contentType: String
    public let sizeBytes: Int64
    public let sha256: String?
    public let originalFilename: String?

    public init(contentType: String,
                sizeBytes: Int64,
                sha256: String?,
                originalFilename: String?) {
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.originalFilename = originalFilename
    }
}

public struct CompleteResponse: Sendable, Codable, Equatable {
    public let assetId: UUID
    public let shortUrl: URL
    public let token: String
    public let expiresAt: Date
    public let deleteAfter: Date
    public let linkStatus: String
    public let retentionPolicy: String

    public init(assetId: UUID,
                shortUrl: URL,
                token: String,
                expiresAt: Date,
                deleteAfter: Date,
                linkStatus: String,
                retentionPolicy: String) {
        self.assetId = assetId
        self.shortUrl = shortUrl
        self.token = token
        self.expiresAt = expiresAt
        self.deleteAfter = deleteAfter
        self.linkStatus = linkStatus
        self.retentionPolicy = retentionPolicy
    }
}

public struct FailRequest: Sendable, Codable, Equatable {
    public let errorCode: String
    public let message: String?

    public init(errorCode: String, message: String?) {
        self.errorCode = errorCode
        self.message = message
    }
}

public struct RevokeResponse: Sendable, Codable, Equatable {
    public let ok: Bool
    public let linkStatus: String
    public let revokedAt: Date

    public init(ok: Bool, linkStatus: String, revokedAt: Date) {
        self.ok = ok
        self.linkStatus = linkStatus
        self.revokedAt = revokedAt
    }
}

public struct HistoryItem: Sendable, Codable, Identifiable, Equatable {
    public let assetId: UUID
    public let token: String
    public let shortUrl: URL
    public let contentType: String
    public let sizeBytes: Int64
    public let originalFilename: String?
    public let createdAt: Date
    public let expiresAt: Date
    public let deleteAfter: Date
    public let linkStatus: String
    public let retentionPolicy: String
    public let accessCount: Int64

    public var id: UUID { assetId }

    public init(assetId: UUID,
                token: String,
                shortUrl: URL,
                contentType: String,
                sizeBytes: Int64,
                originalFilename: String?,
                createdAt: Date,
                expiresAt: Date,
                deleteAfter: Date,
                linkStatus: String,
                retentionPolicy: String,
                accessCount: Int64) {
        self.assetId = assetId
        self.token = token
        self.shortUrl = shortUrl
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.originalFilename = originalFilename
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.deleteAfter = deleteAfter
        self.linkStatus = linkStatus
        self.retentionPolicy = retentionPolicy
        self.accessCount = accessCount
    }
}

public struct HistoryPage: Sendable, Codable, Equatable {
    public let items: [HistoryItem]
    public let nextCursor: String?

    public init(items: [HistoryItem], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}
