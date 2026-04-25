import Foundation
import OSLog
import SwiftData

public actor UploadOrchestrator {
    private let apiClient: APIClientProtocol
    private let store: SwiftDataStore
    private let repository: UploadJobRepository
    private let clipboard: ClipboardProtocol
    private let usageTracker: UsageTrackerProtocol
    private let persistenceEvents: PersistenceEventStream
    private let log = Logger(subsystem: Log.subsystem, category: "upload")

    private let baseDelay: TimeInterval = 2
    private let maxDelay: TimeInterval = 60
    private let maxAttempts: Int = 5

    public init(apiClient: APIClientProtocol,
                store: SwiftDataStore,
                clipboard: ClipboardProtocol,
                usageTracker: UsageTrackerProtocol = UsageTracker.shared,
                persistenceEvents: PersistenceEventStream = .shared) {
        self.apiClient = apiClient
        self.store = store
        self.repository = UploadJobRepository(store: store)
        self.clipboard = clipboard
        self.usageTracker = usageTracker
        self.persistenceEvents = persistenceEvents
    }

    public func handleTaskSuccess(clientJobId: UUID, etag: String?) async {
        _ = etag // WHY: retained for API parity but the backend no longer consumes the S3 ETag.
        do {
            try await repository.updateStatus(clientJobId: clientJobId, status: .completing)
            await MainActor.run {
                UploadProgressMonitor.shared.updateStage(clientJobId: clientJobId,
                                                         stage: .finalizing,
                                                         progress: 1)
            }
            guard let entity = try await repository.findByClientJobId(clientJobId),
                  let remoteUploadId = entity.remoteUploadId else {
                log.error("No upload id for job \(clientJobId.uuidString, privacy: .public)")
                return
            }
            let completion = try await apiClient.completeUpload(
                uploadId: remoteUploadId,
                request: CompleteRequest(contentType: entity.contentType,
                                         sizeBytes: entity.sizeBytes,
                                         sha256: entity.sha256,
                                         originalFilename: entity.originalFilename)
            )
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

    /// Tier 2: multipart's caller already has the /complete response in hand
    /// (unlike single-PUT where the URLSession delegate fires /complete for
    /// us). Reuse `recordSuccess` so the post-complete bookkeeping stays in
    /// one place — usage counter, clipboard guard, Live Activity transition.
    public func handleMultipartCompletion(clientJobId: UUID,
                                          completion: CompleteResponse,
                                          contentType: String,
                                          sizeBytes: Int64,
                                          filename: String?) async {
        do {
            try await recordSuccess(clientJobId: clientJobId,
                                    completion: completion,
                                    contentType: contentType,
                                    sizeBytes: sizeBytes,
                                    filename: filename)
        } catch {
            log.error("multipart recordSuccess failed: \(error.localizedDescription, privacy: .public)")
            await scheduleRetryOrFail(clientJobId: clientJobId, error: error)
        }
    }

    public func handleTaskFailure(clientJobId: UUID, error: Error) async {
        log.error("upload task failed \(clientJobId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        await scheduleRetryOrFail(clientJobId: clientJobId, error: error)
    }

    /// Tier 1: presign returned a pending shortUrl. Copy it to clipboard
    /// immediately and persist that fact so `/complete` doesn't re-copy.
    public func recordPendingLink(clientJobId: UUID,
                                  token: String,
                                  shortUrl: URL) async {
        _ = token // reserved for future wiring (telemetry / banner contract)
        clipboard.copy(shortUrl.absoluteString)
        do {
            try await repository.markLinkCopied(clientJobId: clientJobId, shortURL: shortUrl)
        } catch {
            log.error("markLinkCopied failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func recordDedupe(clientJobId: UUID,
                             dedupe: DedupeInfo,
                             contentType: String,
                             sizeBytes: Int64,
                             filename: String?) async throws {
        try await repository.updateStatus(clientJobId: clientJobId, status: .deduped)
        try await repository.markCompleted(clientJobId: clientJobId,
                                           assetId: dedupe.assetId,
                                           shortURL: dedupe.shortUrl,
                                           expiresAt: dedupe.expiresAt,
                                           deleteAfter: dedupe.deleteAfter)
        try await writeShareLink(token: dedupe.token,
                                 assetId: dedupe.assetId,
                                 shortURL: dedupe.shortUrl,
                                 contentType: contentType,
                                 sizeBytes: sizeBytes,
                                 filename: filename,
                                 expiresAt: dedupe.expiresAt,
                                 deleteAfter: dedupe.deleteAfter,
                                 linkStatus: "active",
                                 retentionPolicy: dedupe.retentionPolicy)
        clipboard.copy(dedupe.shortUrl.absoluteString)
        await LiveActivityController.shared.finishSuccess(clientJobId: clientJobId,
                                                          shortUrl: dedupe.shortUrl.absoluteString,
                                                          expiresAt: dedupe.expiresAt)
        await MainActor.run {
            UploadProgressMonitor.shared.finishSuccess(clientJobId: clientJobId,
                                                       shortUrl: dedupe.shortUrl.absoluteString)
        }
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
                        let completion = try await apiClient.completeUpload(
                            uploadId: uploadId,
                            request: CompleteRequest(contentType: job.contentType,
                                                     sizeBytes: job.sizeBytes,
                                                     sha256: job.sha256,
                                                     originalFilename: job.originalFilename)
                        )
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
        // Tier 1: capture whether presign already copied the short URL before
        // we overwrite the entity with the final completion data.
        let linkAlreadyCopied = (try? await repository.snapshot(clientJobId: clientJobId))?.linkAlreadyCopied ?? false
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
        // WHY: a successful /complete is the canonical "upload happened" signal
        // — increment the per-UTC-day Free-tier counter exactly once per fresh
        // upload. Dedupe responses (recordDedupe path) explicitly skip this
        // because the server recognized idempotency and didn't consume quota.
        _ = await usageTracker.increment()
        // Tier 1: if presign already pushed the short URL to clipboard the
        // user may have pasted it elsewhere — don't clobber that by re-copying.
        if !linkAlreadyCopied {
            clipboard.copy(completion.shortUrl.absoluteString)
        }
        await LiveActivityController.shared.finishSuccess(clientJobId: clientJobId,
                                                          shortUrl: completion.shortUrl.absoluteString,
                                                          expiresAt: completion.expiresAt)
        await MainActor.run {
            UploadProgressMonitor.shared.finishSuccess(clientJobId: clientJobId,
                                                       shortUrl: completion.shortUrl.absoluteString)
        }
    }

    /// Bundle finished: 1 row for the bundle link, N child rows for each asset.
    /// Clipboard gets the bundle URL exactly once; usage counter takes one bump
    /// per file (cap is per-file, not per-bundle).
    public func recordBundleSuccess(bundle: BundleUploadJob,
                                    completedAssets: [BundleCompletedAsset]) async {
        let context = store.backgroundContext()
        let token = bundle.bundleToken
        let descriptor = FetchDescriptor<ShareLinkEntity>(predicate: #Predicate { $0.token == token })
        do {
            let existing = try context.fetch(descriptor).first
            // Earliest expiry across the bundle wins — the server enforces
            // policy uniformly, so all jobs share it; pick the first non-nil.
            let expires = bundle.jobs.compactMap(\.expiresAt).min() ?? Date().addingTimeInterval(86_400)
            let deleteAfter = bundle.jobs.compactMap(\.deleteAfter).max() ?? expires.addingTimeInterval(86_400)
            // Aggregate display values. Filename/contentType collapse to a
            // synthetic "N files" descriptor — the bundle preview page renders
            // the real list; this is only for the local history row's headline.
            let aggregateSize = completedAssets.map(\.sizeBytes).reduce(0, +)
            let headlineFilename = "\(completedAssets.count) files"

            let entity: ShareLinkEntity
            if let existing {
                existing.shortURLString = bundle.bundleShortUrl.absoluteString
                existing.expiresAt = expires
                existing.deleteAfter = deleteAfter
                existing.linkStatus = LinkStatus.active.rawValue
                existing.contentType = "application/x-bundle"
                existing.sizeBytes = aggregateSize
                existing.originalFilename = headlineFilename
                existing.isBundle = true
                // Replace any prior children to keep displayOrder consistent.
                existing.bundledAssets.removeAll()
                entity = existing
            } else {
                entity = ShareLinkEntity(token: token,
                                         assetId: ShareLinkEntity.bundleSentinelAssetId,
                                         shortURLString: bundle.bundleShortUrl.absoluteString,
                                         createdAt: Date(),
                                         visibility: .unlisted,
                                         expiresAt: expires,
                                         deleteAfter: deleteAfter,
                                         linkStatus: LinkStatus.active.rawValue,
                                         retentionPolicy: bundle.jobs.first?.retentionPolicy.rawValue ?? RetentionPolicy.default.rawValue,
                                         contentType: "application/x-bundle",
                                         sizeBytes: aggregateSize,
                                         originalFilename: headlineFilename,
                                         isBundle: true,
                                         bundledAssets: [])
                context.insert(entity)
            }

            for (index, completed) in completedAssets.enumerated() {
                let child = BundledAssetEntity(assetId: completed.assetId,
                                               filename: completed.filename,
                                               sizeBytes: completed.sizeBytes,
                                               contentType: completed.contentType,
                                               displayOrder: index,
                                               shareLink: entity)
                context.insert(child)
                entity.bundledAssets.append(child)
            }
            try context.save()
            await persistenceEvents.emit(existing == nil
                                         ? .shareLinkInserted(token: token)
                                         : .shareLinkUpdated(token: token))
        } catch {
            log.error("recordBundleSuccess persist failed: \(error.localizedDescription, privacy: .public)")
        }

        clipboard.copy(bundle.bundleShortUrl.absoluteString)
        // Per-file cap accounting — N files = N quota units.
        for _ in 0..<bundle.jobs.count {
            _ = await usageTracker.increment()
        }
        // End the bundle Live Activity. No-op on macOS; on iOS the success
        // pill briefly stays on the DI before the dismissal policy collects.
        let expires = bundle.jobs.compactMap(\.expiresAt).min() ?? Date().addingTimeInterval(86_400)
        await LiveActivityController.shared.finishBundleSuccess(
            bundleToken: bundle.bundleToken,
            bundleShortUrl: bundle.bundleShortUrl.absoluteString,
            expiresAt: expires
        )
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
            await persistenceEvents.emit(.shareLinkUpdated(token: token))
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
        await persistenceEvents.emit(.shareLinkInserted(token: token))
    }

    private func applyRevocation(token: String, status: String, revokedAt: Date) async throws {
        let context = store.backgroundContext()
        let descriptor = FetchDescriptor<ShareLinkEntity>(predicate: #Predicate { $0.token == token })
        guard let entity = try context.fetch(descriptor).first else { return }
        entity.linkStatus = status
        entity.revokedAt = revokedAt
        try context.save()
        await persistenceEvents.emit(.shareLinkUpdated(token: token))
    }

    private func scheduleRetryOrFail(clientJobId: UUID, error: Error) async {
        do {
            guard let entity = try await repository.findByClientJobId(clientJobId) else { return }
            let attempts = entity.attemptCount + 1
            if attempts > maxAttempts {
                try await repository.markFailed(clientJobId: clientJobId, error: error.localizedDescription)
                await LiveActivityController.shared.finishFailure(clientJobId: clientJobId,
                                                                  reason: error.localizedDescription)
                await MainActor.run {
                    UploadProgressMonitor.shared.finishFailure(clientJobId: clientJobId,
                                                               reason: error.localizedDescription)
                }
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
