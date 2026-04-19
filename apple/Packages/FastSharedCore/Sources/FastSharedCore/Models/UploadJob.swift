import Foundation

public enum UploadJobStatus: String, Sendable, Codable, CaseIterable {
    case queued
    case presigning
    case uploading
    case completing
    case completed
    case failed
    case deduped
}

public struct UploadJob: Sendable, Codable, Identifiable, Equatable {
    public var id: UUID { clientJobId }

    public let clientJobId: UUID
    public var status: UploadJobStatus
    public var progress: Double
    public var attemptCount: Int
    public let contentType: String
    public let sizeBytes: Int64
    public var sha256: String?
    public var originalFilename: String?
    public var remoteUploadId: String?
    public var remoteAssetId: String?
    public var shortURL: URL?
    public var errorMessage: String?
    public let createdAt: Date
    public var updatedAt: Date
    public let stagedRelativePath: String
    public var retentionPolicy: RetentionPolicy
    public var expiresAt: Date?
    public var deleteAfter: Date?

    public init(clientJobId: UUID = UUID(),
                status: UploadJobStatus = .queued,
                progress: Double = 0,
                attemptCount: Int = 0,
                contentType: String,
                sizeBytes: Int64,
                sha256: String? = nil,
                originalFilename: String? = nil,
                remoteUploadId: String? = nil,
                remoteAssetId: String? = nil,
                shortURL: URL? = nil,
                errorMessage: String? = nil,
                createdAt: Date = Date(),
                updatedAt: Date = Date(),
                stagedRelativePath: String,
                retentionPolicy: RetentionPolicy = .default,
                expiresAt: Date? = nil,
                deleteAfter: Date? = nil) {
        self.clientJobId = clientJobId
        self.status = status
        self.progress = progress
        self.attemptCount = attemptCount
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.originalFilename = originalFilename
        self.remoteUploadId = remoteUploadId
        self.remoteAssetId = remoteAssetId
        self.shortURL = shortURL
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.stagedRelativePath = stagedRelativePath
        self.retentionPolicy = retentionPolicy
        self.expiresAt = expiresAt
        self.deleteAfter = deleteAfter
    }
}
