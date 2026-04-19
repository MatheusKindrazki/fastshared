import Foundation
import OSLog
import SwiftData

public actor UploadOrchestrator {
    private let apiClient: APIClientProtocol
    private let store: SwiftDataStore
    private let repository: UploadJobRepository
    private let clipboard: ClipboardProtocol
    private let log = Logger(subsystem: Log.subsystem, category: "upload")

    private let baseDelay: TimeInterval = 2
    private let maxDelay: TimeInterval = 60
    private let maxAttempts: Int = 5

    public init(apiClient: APIClientProtocol, store: SwiftDataStore, clipboard: ClipboardProtocol) {
        self.apiClient = apiClient
        self.store = store
        self.repository = UploadJobRepository(store: store)
        self.clipboard = clipboard
    }

    public func handleTaskSuccess(clientJobId: UUID, etag: String?) async {
        do {
            try await repository.updateStatus(clientJobId: clientJobId, status: .completing)
            guard let entity = try await repository.findByClientJobId(clientJobId),
                  let remoteUploadId = entity.remoteUploadId else {
                log.error("No upload id for job \(clientJobId.uuidString, privacy: .public)")
                return
            }
            let sha = entity.sha256
            let completion = try await apiClient.completeUpload(uploadId: remoteUploadId,
                                                                request: CompleteRequest(etag: etag, sha256: sha))
            try await recordSuccess(clientJobId: clientJobId,
                                    completion: completion,
                                    contentType: entity.contentType,
                                    sizeBytes: entity.sizeBytes,
                                    filename: entity.originalFilename)
        } catch {
            log.error("completeUpload failed: \(error.localizedDescription, privacy: .public)")
            await scheduleRetryOrFail(clientJobId: clientJobId, error: error)
        }
    }

    public func handleTaskFailure(clientJobId: UUID, error: Error) async {
        log.error("upload task failed \(clientJobId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        await scheduleRetryOrFail(clientJobId: clientJobId, error: error)
    }

    public func recordDedupe(clientJobId: UUID,
                             dedupe: DedupeInfo,
                             contentType: String,
                             sizeBytes: Int64,
                             filename: String?) async throws {
        try await repository.updateStatus(clientJobId: clientJobId, status: .deduped)
        try await repository.markCompleted(clientJobId: clientJobId,
                                           assetId: dedupe.assetId,
                                           shortURL: dedupe.shortURL,
                                           expiresAt: dedupe.expiresAt,
                                           deleteAfter: dedupe.deleteAfter)
        try await writeShareLink(token: dedupe.token,
                                 assetId: dedupe.assetId,
                                 shortURL: dedupe.shortURL,
                                 contentType: contentType,
                                 sizeBytes: sizeBytes,
                                 filename: filename,
                                 expiresAt: dedupe.expiresAt,
                                 deleteAfter: dedupe.deleteAfter,
                                 linkStatus: "active",
                                 retentionPolicy: dedupe.retentionPolicy)
        clipboard.copy(dedupe.shortURL.absoluteString)
    }

    public func revoke(token: String) async throws {
        let response = try await apiClient.revokeLink(token: token)
        try await applyRevocation(token: token, status: response.linkStatus, revokedAt: response.revokedAt)
    }

    public func lazyMarkExpiredIfNeeded(token: String) async {
        // WHY: server is the source of truth for status, but the local row is what the UI binds to;
        // flip stale active rows to expired so the countdown badge matches reality without waiting for refresh.
        let context = store.backgroundContext()
        let descriptor = FetchDescriptor<ShareLinkEntity>(predicate: #Predicate { $0.token == token })
        do {
            if let match = try context.fetch(descriptor).first,
               match.linkStatus == LinkStatus.active.rawValue,
               match.expiresAt <= Date() {
                match.linkStatus = LinkStatus.expired.rawValue
                try context.save()
            }
        } catch {
            log.error("lazyMarkExpired failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func resumeUnfinishedJobs() async {
        do {
            let unfinished = try await repository.list(statuses: [.uploading, .completing, .presigning])
            for job in unfinished {
                log.info("reconciling job \(job.clientJobId.uuidString, privacy: .public) in state \(job.status.rawValue, privacy: .public)")
                if job.status == .completing, let uploadId = job.remoteUploadId {
                    do {
                        let completion = try await apiClient.completeUpload(uploadId: uploadId,
                                                                            request: CompleteRequest(etag: nil, sha256: job.sha256))
                        try await recordSuccess(clientJobId: job.clientJobId,
                                                completion: completion,
                                                contentType: job.contentType,
                                                sizeBytes: job.sizeBytes,
                                                filename: job.originalFilename)
                    } catch {
                        await scheduleRetryOrFail(clientJobId: job.clientJobId, error: error)
                    }
                }
            }
        } catch {
            log.error("resumeUnfinishedJobs failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recordSuccess(clientJobId: UUID,
                               completion: CompleteResponse,
                               contentType: String,
                               sizeBytes: Int64,
                               filename: String?) async throws {
        try await repository.markCompleted(clientJobId: clientJobId,
                                           assetId: completion.assetId,
                                           shortURL: completion.shortUrl,
                                           expiresAt: completion.expiresAt,
                                           deleteAfter: completion.deleteAfter)
        try await writeShareLink(token: completion.token,
                                 assetId: completion.assetId,
                                 shortURL: completion.shortUrl,
                                 contentType: contentType,
                                 sizeBytes: sizeBytes,
                                 filename: filename,
                                 expiresAt: completion.expiresAt,
                                 deleteAfter: completion.deleteAfter,
                                 linkStatus: completion.linkStatus,
                                 retentionPolicy: completion.retentionPolicy)
        clipboard.copy(completion.shortUrl.absoluteString)
    }

    private func writeShareLink(token: String,
                                assetId: UUID,
                                shortURL: URL,
                                contentType: String,
                                sizeBytes: Int64,
                                filename: String?,
                                expiresAt: Date,
                                deleteAfter: Date,
                                linkStatus: String,
                                retentionPolicy: String) async throws {
        let context = store.backgroundContext()
        let descriptor = FetchDescriptor<ShareLinkEntity>(predicate: #Predicate { $0.token == token })
        if let existing = try context.fetch(descriptor).first {
            existing.assetId = assetId
            existing.shortURLString = shortURL.absoluteString
            existing.expiresAt = expiresAt
            existing.deleteAfter = deleteAfter
            existing.linkStatus = linkStatus
            existing.retentionPolicy = retentionPolicy
            existing.contentType = contentType
            existing.sizeBytes = sizeBytes
            existing.originalFilename = filename
            try context.save()
            return
        }
        let entity = ShareLinkEntity(token: token,
                                     assetId: assetId,
                                     shortURLString: shortURL.absoluteString,
                                     createdAt: Date(),
                                     visibility: .unlisted,
                                     expiresAt: expiresAt,
                                     deleteAfter: deleteAfter,
                                     linkStatus: linkStatus,
                                     retentionPolicy: retentionPolicy,
                                     contentType: contentType,
                                     sizeBytes: sizeBytes,
                                     originalFilename: filename)
        context.insert(entity)
        try context.save()
    }

    private func applyRevocation(token: String, status: String, revokedAt: Date) async throws {
        let context = store.backgroundContext()
        let descriptor = FetchDescriptor<ShareLinkEntity>(predicate: #Predicate { $0.token == token })
        guard let entity = try context.fetch(descriptor).first else { return }
        entity.linkStatus = status
        entity.revokedAt = revokedAt
        try context.save()
    }

    private func scheduleRetryOrFail(clientJobId: UUID, error: Error) async {
        do {
            guard let entity = try await repository.findByClientJobId(clientJobId) else { return }
            let attempts = entity.attemptCount + 1
            if attempts > maxAttempts {
                try await repository.markFailed(clientJobId: clientJobId, error: error.localizedDescription)
                return
            }
            try await repository.markFailed(clientJobId: clientJobId, error: error.localizedDescription)
            let delay = backoffDelay(attempt: attempts)
            log.info("retrying \(clientJobId.uuidString, privacy: .public) after \(delay, privacy: .public)s")
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            try await repository.updateStatus(clientJobId: clientJobId, status: .queued)
            // WHY: we do not re-schedule the PUT here - the caller (UploadService) watches queued jobs.
            // A future iteration may kick a scheduler directly.
        } catch {
            log.error("retry bookkeeping failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func backoffDelay(attempt: Int) -> TimeInterval {
        let exponential = baseDelay * pow(2.0, Double(max(0, attempt - 1)))
        let capped = min(maxDelay, exponential)
        let jitter = Double.random(in: 0...(capped * 0.25))
        return capped + jitter
    }
}
