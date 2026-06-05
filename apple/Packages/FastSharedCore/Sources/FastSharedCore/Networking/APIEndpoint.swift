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
    case signInApple
    case requestUpload
    case requestBatchUpload
    case completeUpload(uploadId: String)
    case failUpload(uploadId: String)
    case abortMultipartUpload(uploadId: String)
    case fetchHistory
    case deleteAsset(id: UUID)
    case revokeLink(token: String)
    case iapVerify
    case me
    case pricingFlags
    case deleteAccount

    public var path: String {
        switch self {
        case .registerDevice: return "/v1/devices"
        case .signInApple: return "/v1/auth/apple"
        case .requestUpload: return "/v1/uploads"
        case .requestBatchUpload: return "/v1/uploads/batch"
        case .completeUpload(let id): return "/v1/uploads/\(id)/complete"
        case .failUpload(let id): return "/v1/uploads/\(id)/fail"
        case .abortMultipartUpload(let id): return "/v1/uploads/\(id)/abort-multipart"
        case .fetchHistory: return "/v1/history"
        case .deleteAsset(let id): return "/v1/assets/\(id.uuidString)"
        case .revokeLink(let token): return "/v1/links/\(token)/revoke"
        case .iapVerify: return "/v1/iap/verify"
        case .me: return "/v1/me"
        case .pricingFlags: return "/v1/pricing-flags"
        case .deleteAccount: return "/v1/account"
        }
    }

    public var method: HTTPMethod {
        switch self {
        case .registerDevice, .signInApple, .requestUpload, .requestBatchUpload, .completeUpload, .failUpload, .abortMultipartUpload, .revokeLink, .iapVerify: return .post
        case .fetchHistory, .me, .pricingFlags: return .get
        case .deleteAsset, .deleteAccount: return .delete
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

/// Tier 2: the presign response's `upload` slot carries either a single-PUT
/// presign or a multipart plan, discriminated by `mode`. The server always
/// emits `mode` on new deploys; when it's missing we default to `single` so a
/// client with this enum decodes a legacy response correctly.
public enum UploadInstruction: Sendable, Codable, Equatable {
    case single(SingleInstruction)
    case multipart(MultipartInstruction)

    public struct SingleInstruction: Sendable, Codable, Equatable {
        public let url: URL
        public let method: String
        public let headers: [String: String]
        public let expiresAt: Date

        public init(url: URL, method: String, headers: [String: String], expiresAt: Date) {
            self.url = url
            self.method = method
            self.headers = headers
            self.expiresAt = expiresAt
        }
    }

    public struct MultipartInstruction: Sendable, Codable, Equatable {
        public let multipartUploadId: String
        public let partSize: Int
        public let parts: [PartURL]
        public let expiresAt: Date

        public struct PartURL: Sendable, Codable, Equatable {
            public let partNumber: Int
            public let url: URL
            public let method: String

            public init(partNumber: Int, url: URL, method: String) {
                self.partNumber = partNumber
                self.url = url
                self.method = method
            }
        }

        public init(multipartUploadId: String,
                    partSize: Int,
                    parts: [PartURL],
                    expiresAt: Date) {
            self.multipartUploadId = multipartUploadId
            self.partSize = partSize
            self.parts = parts
            self.expiresAt = expiresAt
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case url
        case method
        case headers
        case expiresAt
        case multipartUploadId
        case partSize
        case parts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "single"
        switch mode {
        case "single":
            self = .single(SingleInstruction(
                url: try container.decode(URL.self, forKey: .url),
                method: try container.decode(String.self, forKey: .method),
                headers: try container.decode([String: String].self, forKey: .headers),
                expiresAt: try container.decode(Date.self, forKey: .expiresAt)
            ))
        case "multipart":
            self = .multipart(MultipartInstruction(
                multipartUploadId: try container.decode(String.self, forKey: .multipartUploadId),
                partSize: try container.decode(Int.self, forKey: .partSize),
                parts: try container.decode([MultipartInstruction.PartURL].self, forKey: .parts),
                expiresAt: try container.decode(Date.self, forKey: .expiresAt)
            ))
        default:
            throw DecodingError.dataCorruptedError(forKey: .mode,
                                                   in: container,
                                                   debugDescription: "unknown upload mode \(mode)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .single(let s):
            try container.encode("single", forKey: .mode)
            try container.encode(s.url, forKey: .url)
            try container.encode(s.method, forKey: .method)
            try container.encode(s.headers, forKey: .headers)
            try container.encode(s.expiresAt, forKey: .expiresAt)
        case .multipart(let m):
            try container.encode("multipart", forKey: .mode)
            try container.encode(m.multipartUploadId, forKey: .multipartUploadId)
            try container.encode(m.partSize, forKey: .partSize)
            try container.encode(m.parts, forKey: .parts)
            try container.encode(m.expiresAt, forKey: .expiresAt)
        }
    }
}

// Backward-compat shim: existing call sites that build a single-PUT instruction
// inline used `UploadInstruction(url:method:headers:expiresAt:)`. Keep that
// shape working so the refactor doesn't ripple across tests + share ext.
public extension UploadInstruction {
    init(url: URL, method: String, headers: [String: String], expiresAt: Date) {
        self = .single(SingleInstruction(url: url,
                                         method: method,
                                         headers: headers,
                                         expiresAt: expiresAt))
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
    // Tier 1: optimistic share_link minted at presign so the client can copy
    // the URL before the bytes finish uploading. Nil on dedup responses.
    public let token: String?
    public let shortUrl: URL?
    public let linkStatus: String?
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
                token: String? = nil,
                shortUrl: URL? = nil,
                linkStatus: String? = nil,
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
        self.token = token
        self.shortUrl = shortUrl
        self.linkStatus = linkStatus
        self.deduped = deduped
    }
}

// MARK: - Bundle batch presign

/// Per-item slot in `POST /uploads/batch`. `clientJobId` is sent as a string to
/// match the backend zod schema; UUID-typed callers stringify on encode.
public struct BatchUploadItemRequest: Sendable, Codable, Equatable {
    public let clientJobId: String
    public let contentType: String
    public let sizeBytes: Int64
    public let sha256: String?
    public let originalFilename: String?

    public init(clientJobId: String,
                contentType: String,
                sizeBytes: Int64,
                sha256: String? = nil,
                originalFilename: String? = nil) {
        self.clientJobId = clientJobId
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.originalFilename = originalFilename
    }
}

/// Request body for `POST /uploads/batch`. Mirrors the single-file `PresignRequest`
/// shape but in array form. Server enforces 2..=50 items.
public struct BatchPresignRequest: Sendable, Codable, Equatable {
    public let retentionPolicy: String
    public let visibility: String
    public let customTtlSeconds: Int?
    public let items: [BatchUploadItemRequest]

    public init(retentionPolicy: String,
                visibility: String,
                customTtlSeconds: Int? = nil,
                items: [BatchUploadItemRequest]) {
        self.retentionPolicy = retentionPolicy
        self.visibility = visibility
        self.customTtlSeconds = customTtlSeconds
        self.items = items
    }
}

/// One item in the bundle presign response. `upload` reuses `UploadInstruction`
/// so single-PUT and multipart paths flow through the same code as POST /uploads.
public struct BatchPresignItem: Sendable, Codable, Equatable {
    public let clientJobId: String
    public let uploadId: String
    public let storageKey: String
    public let contentType: String
    public let sizeBytes: Int64
    public let upload: UploadInstruction

    public init(clientJobId: String,
                uploadId: String,
                storageKey: String,
                contentType: String,
                sizeBytes: Int64,
                upload: UploadInstruction) {
        self.clientJobId = clientJobId
        self.uploadId = uploadId
        self.storageKey = storageKey
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.upload = upload
    }
}

/// Response for `POST /uploads/batch`. The server pre-mints the bundle share_link
/// (status=pending) and returns presigned URLs for every item; client fans out
/// PUT R2 in parallel and posts /complete per item.
public struct BatchPresignResponse: Sendable, Codable, Equatable {
    public let bundleToken: String
    public let bundleShortUrl: URL
    public let expiresAt: Date
    public let deleteAfter: Date
    public let retentionPolicy: String
    public let itemCount: Int
    public let items: [BatchPresignItem]
    /// Set when Free-tier silently clamped a longer retention back to oneDay.
    public let retentionClamped: Bool?
    public let clampedTo: String?

    public init(bundleToken: String,
                bundleShortUrl: URL,
                expiresAt: Date,
                deleteAfter: Date,
                retentionPolicy: String,
                itemCount: Int,
                items: [BatchPresignItem],
                retentionClamped: Bool? = nil,
                clampedTo: String? = nil) {
        self.bundleToken = bundleToken
        self.bundleShortUrl = bundleShortUrl
        self.expiresAt = expiresAt
        self.deleteAfter = deleteAfter
        self.retentionPolicy = retentionPolicy
        self.itemCount = itemCount
        self.items = items
        self.retentionClamped = retentionClamped
        self.clampedTo = clampedTo
    }
}

public struct CompleteRequest: Sendable, Codable, Equatable {
    public let contentType: String
    public let sizeBytes: Int64
    public let sha256: String?
    public let originalFilename: String?
    /// Tier 2: present only when the upload took the multipart path. Server
    /// sorts by partNumber defensively but we still send ascending to be clear.
    public let multipart: MultipartCompletion?

    public struct MultipartCompletion: Sendable, Codable, Equatable {
        public let parts: [PartResult]

        public struct PartResult: Sendable, Codable, Equatable {
            public let partNumber: Int
            public let eTag: String

            public init(partNumber: Int, eTag: String) {
                self.partNumber = partNumber
                self.eTag = eTag
            }
        }

        public init(parts: [PartResult]) {
            self.parts = parts
        }
    }

    public init(contentType: String,
                sizeBytes: Int64,
                sha256: String?,
                originalFilename: String?,
                multipart: MultipartCompletion? = nil) {
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.originalFilename = originalFilename
        self.multipart = multipart
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

// MARK: - IAP + pricing types (Plan A backend contract)

/// Body for `POST /v1/iap/verify`. Sends a single signed StoreKit 2 transaction JWS
/// representation — the backend decodes + validates against Apple's App Store Server API.
public struct IAPVerifyRequest: Sendable, Codable, Equatable {
    public let jwsRepresentation: String

    public init(jwsRepresentation: String) {
        self.jwsRepresentation = jwsRepresentation
    }
}

/// Server DTO for tier caps, mirroring `TierCaps` but decoupled so the backend can tune
/// values without requiring a client rebuild.
public struct TierCapsDTO: Sendable, Codable, Equatable {
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

    public func toCaps() -> TierCaps {
        TierCaps(dailyUploadLimit: dailyUploadLimit,
                 maxFileSizeBytes: maxFileSizeBytes,
                 maxRetentionSeconds: maxRetentionSeconds,
                 allowsCloudSync: allowsCloudSync)
    }
}

public extension TierCaps {
    /// Projects the in-memory caps back to a wire DTO (used in tests + cache write).
    func toDTO() -> TierCapsDTO {
        TierCapsDTO(dailyUploadLimit: dailyUploadLimit,
                    maxFileSizeBytes: maxFileSizeBytes,
                    maxRetentionSeconds: maxRetentionSeconds,
                    allowsCloudSync: allowsCloudSync)
    }
}

/// Response for `POST /v1/iap/verify` and `GET /v1/me`. `tier` is the ASC product stem
/// (`"monthly"`, `"annual"`, `"lifetime"`) or nil for Free; backend is authoritative.
public struct IAPVerifyResponse: Sendable, Codable, Equatable {
    public let isPro: Bool
    public let tier: String?
    public let expiresAt: Date?
    public let caps: TierCapsDTO

    public init(isPro: Bool,
                tier: String?,
                expiresAt: Date?,
                caps: TierCapsDTO) {
        self.isPro = isPro
        self.tier = tier
        self.expiresAt = expiresAt
        self.caps = caps
    }
}

/// Response for `GET /v1/me`. Same shape as `IAPVerifyResponse` — aliased for intent.
public struct MeResponse: Sendable, Codable, Equatable {
    public let isPro: Bool
    public let tier: String?
    public let expiresAt: Date?
    public let caps: TierCapsDTO

    public init(isPro: Bool,
                tier: String?,
                expiresAt: Date?,
                caps: TierCapsDTO) {
        self.isPro = isPro
        self.tier = tier
        self.expiresAt = expiresAt
        self.caps = caps
    }
}

/// Response for `GET /v1/pricing-flags`. Drives the client-side "Early Access" lifetime badge.
public struct PricingFlags: Sendable, Codable, Equatable {
    public let earlyAccessLifetimeActive: Bool
    public let earlyAccessEndsAt: Date?

    public init(earlyAccessLifetimeActive: Bool,
                earlyAccessEndsAt: Date?) {
        self.earlyAccessLifetimeActive = earlyAccessLifetimeActive
        self.earlyAccessEndsAt = earlyAccessEndsAt
    }
}
