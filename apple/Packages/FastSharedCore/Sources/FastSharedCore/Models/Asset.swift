import Foundation

public struct Asset: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let contentType: String
    public let sizeBytes: Int64
    public let sha256: String?
    public let createdAt: Date
    public let originalFilename: String?

    public init(id: UUID,
                contentType: String,
                sizeBytes: Int64,
                sha256: String?,
                createdAt: Date,
                originalFilename: String?) {
        self.id = id
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.createdAt = createdAt
        self.originalFilename = originalFilename
    }
}
