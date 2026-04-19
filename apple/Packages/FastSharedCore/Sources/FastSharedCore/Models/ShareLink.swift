import Foundation

public enum Visibility: String, Sendable, Codable, CaseIterable {
    case unlisted
    case publicLink = "public"
    case privateLink = "private"
}

public enum LinkStatus: String, Codable, Sendable {
    case active
    case expired
    case revoked
}

public struct ShareLink: Sendable, Codable, Identifiable, Equatable {
    public var id: String { token }

    public let token: String
    public let assetId: UUID
    public let shortURL: URL
    public let createdAt: Date
    public let visibility: Visibility
    public let expiresAt: Date
    public let deleteAfter: Date
    public let linkStatus: LinkStatus
    public let retentionPolicy: RetentionPolicy
    public let revokedAt: Date?
    public let lastAccessedAt: Date?
    public let accessCount: Int64

    public init(token: String,
                assetId: UUID,
                shortURL: URL,
                createdAt: Date,
                visibility: Visibility,
                expiresAt: Date,
                deleteAfter: Date,
                linkStatus: LinkStatus,
                retentionPolicy: RetentionPolicy,
                revokedAt: Date? = nil,
                lastAccessedAt: Date? = nil,
                accessCount: Int64 = 0) {
        self.token = token
        self.assetId = assetId
        self.shortURL = shortURL
        self.createdAt = createdAt
        self.visibility = visibility
        self.expiresAt = expiresAt
        self.deleteAfter = deleteAfter
        self.linkStatus = linkStatus
        self.retentionPolicy = retentionPolicy
        self.revokedAt = revokedAt
        self.lastAccessedAt = lastAccessedAt
        self.accessCount = accessCount
    }
}
