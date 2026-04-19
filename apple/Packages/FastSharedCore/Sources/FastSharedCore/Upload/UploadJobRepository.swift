import Foundation
import SwiftData

public actor UploadJobRepository {
    private let store: SwiftDataStore

    public init(store: SwiftDataStore) {
        self.store = store
    }

    public func create(_ job: UploadJob) throws {
        let context = store.backgroundContext()
        let entity = UploadJobEntity(clientJobId: job.clientJobId,
                                     status: job.status,
                                     progress: job.progress,
                                     attemptCount: job.attemptCount,
                                     contentType: job.contentType,
                                     sizeBytes: job.sizeBytes,
                                     sha256: job.sha256,
                                     originalFilename: job.originalFilename,
                                     remoteUploadId: job.remoteUploadId,
                                     remoteAssetId: job.remoteAssetId,
                                     shortURLString: job.shortURL?.absoluteString,
                                     errorMessage: job.errorMessage,
                                     createdAt: job.createdAt,
                                     updatedAt: job.updatedAt,
                                     stagedRelativePath: job.stagedRelativePath,
                                     retentionPolicy: job.retentionPolicy.rawValue,
                                     expiresAt: job.expiresAt,
                                     deleteAfter: job.deleteAfter)
        context.insert(entity)
        try context.save()
    }

    public func findByClientJobId(_ id: UUID) throws -> UploadJobEntity? {
        let context = store.backgroundContext()
        let descriptor = FetchDescriptor<UploadJobEntity>(predicate: #Predicate { $0.clientJobId == id })
        return try context.fetch(descriptor).first
    }

    public func updateStatus(clientJobId: UUID, status: UploadJobStatus, error: String? = nil) throws {
        let context = store.backgroundContext()
        let descriptor = FetchDescriptor<UploadJobEntity>(predicate: #Predicate { $0.clientJobId == clientJobId })
        guard let entity = try context.fetch(descriptor).first else { return }
        entity.status = status
        entity.errorMessage = error
        entity.updatedAt = Date()
        try context.save()
    }

    public func updateProgress(clientJobId: UUID, progress: Double) throws {
        let context = store.backgroundContext()
        let descriptor = FetchDescriptor<UploadJobEntity>(predicate: #Predicate { $0.clientJobId == clientJobId })
        guard let entity = try context.fetch(descriptor).first else { return }
        entity.progress = progress
        entity.updatedAt = Date()
        try context.save()
    }

    public func markCompleted(clientJobId: UUID,
                              assetId: UUID,
                              shortURL: URL,
                              expiresAt: Date? = nil,
                              deleteAfter: Date? = nil) throws {
        let context = store.backgroundContext()
        let descriptor = FetchDescriptor<UploadJobEntity>(predicate: #Predicate { $0.clientJobId == clientJobId })
        guard let entity = try context.fetch(descriptor).first else { return }
        entity.status = .completed
        entity.remoteAssetId = assetId.uuidString
        entity.shortURLString = shortURL.absoluteString
        entity.progress = 1
        entity.updatedAt = Date()
        if let expiresAt { entity.expiresAt = expiresAt }
        if let deleteAfter { entity.deleteAfter = deleteAfter }
        try context.save()
    }

    public func markFailed(clientJobId: UUID, error: String) throws {
        let context = store.backgroundContext()
        let descriptor = FetchDescriptor<UploadJobEntity>(predicate: #Predicate { $0.clientJobId == clientJobId })
        guard let entity = try context.fetch(descriptor).first else { return }
        entity.status = .failed
        entity.errorMessage = error
        entity.attemptCount += 1
        entity.updatedAt = Date()
        try context.save()
    }

    public func list(statuses: [UploadJobStatus]) throws -> [UploadJob] {
        let context = store.backgroundContext()
        let raw = statuses.map(\.rawValue)
        let descriptor = FetchDescriptor<UploadJobEntity>(predicate: #Predicate { raw.contains($0.statusRaw) })
        return try context.fetch(descriptor).map { $0.snapshot() }
    }

    public func setPresign(clientJobId: UUID, uploadId: String, assetId: UUID? = nil) throws {
        let context = store.backgroundContext()
        let descriptor = FetchDescriptor<UploadJobEntity>(predicate: #Predicate { $0.clientJobId == clientJobId })
        guard let entity = try context.fetch(descriptor).first else { return }
        entity.remoteUploadId = uploadId
        // WHY: the backend only issues an assetId after /complete, so leave remoteAssetId
        // untouched during presign when the caller has nothing to set.
        if let assetId {
            entity.remoteAssetId = assetId.uuidString
        }
        entity.updatedAt = Date()
        try context.save()
    }

    public func snapshot(clientJobId: UUID) throws -> UploadJob? {
        let context = store.backgroundContext()
        let descriptor = FetchDescriptor<UploadJobEntity>(predicate: #Predicate { $0.clientJobId == clientJobId })
        return try context.fetch(descriptor).first?.snapshot()
    }

    public func findShareLinkForJob(clientJobId: UUID) throws -> ShareLink? {
        let context = store.backgroundContext()
        let jobDescriptor = FetchDescriptor<UploadJobEntity>(predicate: #Predicate { $0.clientJobId == clientJobId })
        guard let job = try context.fetch(jobDescriptor).first,
              let shortString = job.shortURLString,
              let shortURL = URL(string: shortString),
              let assetIdString = job.remoteAssetId,
              let assetId = UUID(uuidString: assetIdString) else { return nil }

        // WHY: the ShareLinkEntity carries the canonical token and timestamps; we look it up by short URL since
        // UploadJobEntity never stores the token directly.
        let linkDescriptor = FetchDescriptor<ShareLinkEntity>(predicate: #Predicate { $0.shortURLString == shortString })
        if let link = try context.fetch(linkDescriptor).first {
            return ShareLink(token: link.token,
                             assetId: link.assetId,
                             shortURL: link.shortURL,
                             createdAt: link.createdAt,
                             visibility: link.visibility,
                             expiresAt: link.expiresAt,
                             deleteAfter: link.deleteAfter,
                             linkStatus: link.status,
                             retentionPolicy: link.retention,
                             revokedAt: link.revokedAt,
                             lastAccessedAt: link.lastAccessedAt,
                             accessCount: link.accessCount)
        }

        // WHY: while the ShareLink row may not yet be written (race on orchestrator), synthesize a minimal
        // payload from the job so the share-extension UI can still unveil the short URL.
        guard let expiresAt = job.expiresAt, let deleteAfter = job.deleteAfter else { return nil }
        return ShareLink(token: shortURL.lastPathComponent,
                         assetId: assetId,
                         shortURL: shortURL,
                         createdAt: job.createdAt,
                         visibility: .unlisted,
                         expiresAt: expiresAt,
                         deleteAfter: deleteAfter,
                         linkStatus: .active,
                         retentionPolicy: RetentionPolicy(rawValue: job.retentionPolicy) ?? .default)
    }
}
