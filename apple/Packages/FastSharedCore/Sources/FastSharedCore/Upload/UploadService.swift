import Foundation
import OSLog
import UniformTypeIdentifiers

/// Fine-grained prepare/finalize phases emitted by `UploadService.enqueue` so
/// the share-extension UI can label the 10-15s gap between tap and first PUT
/// byte (hashing a 125 MB video eats ~4s on iPhone; multipart presign adds
/// another 2-3s). Without this the user sees "0%" frozen and thinks the app hung.
public enum UploadPreparePhase: Sendable {
    /// Hashing the local file. `totalBytes` is always known; `bytesHashed`
    /// ticks every 1 MB chunk so the bar is determinate.
    case hashing(bytesHashed: Int64, totalBytes: Int64)
    /// Presign request in flight (+ multipart init for files > 10 MB).
    /// Indeterminate — server latency is not measurable client-side.
    case presigning
    /// POST /complete in flight after the last R2 PUT landed.
    case finalizing
}

public protocol UploadServiceProtocol: Sendable {
    func enqueue(stagedURL: URL,
                 contentType: String,
                 originalFilename: String?,
                 retentionPolicy: RetentionPolicy) async throws -> UploadJob
    func enqueueDrop(urls: [URL], retentionPolicy: RetentionPolicy) async throws -> EnqueueResult
    func enqueueDrop(urls: [URL],
                     retentionPolicy: RetentionPolicy,
                     progressClientJobId: UUID?) async throws -> EnqueueResult
}

public extension UploadServiceProtocol {
    func enqueue(stagedURL: URL,
                 contentType: String,
                 originalFilename: String?) async throws -> UploadJob {
        try await enqueue(stagedURL: stagedURL,
                          contentType: contentType,
                          originalFilename: originalFilename,
                          retentionPolicy: .default)
    }

    func enqueueDrop(urls: [URL]) async throws -> EnqueueResult {
        try await enqueueDrop(urls: urls, retentionPolicy: RetentionPolicy.defaultFromAppGroup())
    }

    func enqueueDrop(urls: [URL],
                     retentionPolicy: RetentionPolicy,
                     progressClientJobId: UUID?) async throws -> EnqueueResult {
        try await enqueueDrop(urls: urls, retentionPolicy: retentionPolicy)
    }
}

/// Outcome of `enqueueDrop`: a single drop becomes one `UploadJob`; a multi-file
/// drop becomes a `BundleUploadJob` with an aggregated short URL. Callers switch
/// on this so the UI can render either single-file progress or a bundle headline.
public enum EnqueueResult: Sendable {
    case single(UploadJob)
    case bundle(BundleUploadJob)
}

/// Per-asset payload handed to `UploadOrchestrator.recordBundleSuccess` after
/// every item's `/complete` lands. Carries the canonical asset id minted by
/// the backend plus the metadata we need to render the local history row.
public struct BundleCompletedAsset: Sendable, Equatable {
    public let assetId: UUID
    public let filename: String
    public let sizeBytes: Int64
    public let contentType: String

    public init(assetId: UUID, filename: String, sizeBytes: Int64, contentType: String) {
        self.assetId = assetId
        self.filename = filename
        self.sizeBytes = sizeBytes
        self.contentType = contentType
    }
}

/// Aggregate descriptor for a bundle in flight. `aggregateProgress` emits the
/// summed-bytes fraction (0..1) so a single Live Activity / banner can drive
/// from one stream regardless of per-job parallelism.
public struct BundleUploadJob: Sendable {
    public let bundleToken: String
    public let bundleShortUrl: URL
    public let jobs: [UploadJob]
    public let totalBytes: Int64
    public let aggregateProgress: AsyncStream<Double>

    public init(bundleToken: String,
                bundleShortUrl: URL,
                jobs: [UploadJob],
                totalBytes: Int64,
                aggregateProgress: AsyncStream<Double>) {
        self.bundleToken = bundleToken
        self.bundleShortUrl = bundleShortUrl
        self.jobs = jobs
        self.totalBytes = totalBytes
        self.aggregateProgress = aggregateProgress
    }
}

/// Coalesces per-job byte counters into a single normalized 0..1 stream.
/// Actor isolation makes the cross-task updates race-free without a lock.
actor BundleProgressAggregator {
    private var perJob: [UUID: Int64] = [:]
    private let totalBytes: Int64
    private let continuation: AsyncStream<Double>.Continuation
    /// Optional second sink so the Live Activity can be ticked without
    /// multi-consuming the AsyncStream (which only supports one observer).
    private let onTick: (@Sendable (_ bytes: Int64, _ fraction: Double) -> Void)?

    init(totalBytes: Int64,
         continuation: AsyncStream<Double>.Continuation,
         onTick: (@Sendable (_ bytes: Int64, _ fraction: Double) -> Void)? = nil) {
        self.totalBytes = max(1, totalBytes) // guard /0 on empty bundles
        self.continuation = continuation
        self.onTick = onTick
    }

    func update(jobId: UUID, bytes: Int64) {
        // Monotonic floor — late deliveries can't regress a counter past peak.
        let prior = perJob[jobId] ?? 0
        perJob[jobId] = max(prior, bytes)
        let summed = perJob.values.reduce(0, +)
        let fraction = min(1.0, Double(summed) / Double(totalBytes))
        continuation.yield(fraction)
        onTick?(summed, fraction)
    }

    func finish() {
        continuation.yield(1.0)
        continuation.finish()
        onTick?(totalBytes, 1.0)
    }
}

actor PreparationProgressAggregator {
    private var perItem: [UUID: Int64] = [:]
    private let monitorClientJobId: UUID
    private let totalBytes: Int64
    private let stage: UploadProgressMonitor.ActiveUpload.Stage

    init(monitorClientJobId: UUID,
         totalBytes: Int64,
         stage: UploadProgressMonitor.ActiveUpload.Stage) {
        self.monitorClientJobId = monitorClientJobId
        self.totalBytes = max(1, totalBytes)
        self.stage = stage
    }

    func update(itemId: UUID, bytes: Int64) {
        let prior = perItem[itemId] ?? 0
        perItem[itemId] = max(prior, bytes)
        let summed = perItem.values.reduce(0, +)
        let fraction = min(1.0, Double(summed) / Double(totalBytes))
        Task { @MainActor in
            UploadProgressMonitor.shared.updateProgress(
                clientJobId: monitorClientJobId,
                progress: fraction,
                bytesSent: summed,
                bytesTotal: totalBytes,
                stage: stage
            )
        }
    }
}

public actor UploadService: UploadServiceProtocol {
    private let apiClient: APIClientProtocol
    private let store: SwiftDataStore
    private let tokenStore: DeviceTokenStore
    private let background: BackgroundSessionScheduling
    private let orchestrator: UploadOrchestrator
    private let repository: UploadJobRepository
    private let usageTracker: UsageTrackerProtocol
    private let subscriptionStore: SubscriptionStoreProtocol?
    private let log = Logger(subsystem: Log.subsystem, category: "upload")

    public init(apiClient: APIClientProtocol,
                store: SwiftDataStore,
                tokenStore: DeviceTokenStore,
                background: BackgroundSessionScheduling,
                orchestrator: UploadOrchestrator,
                usageTracker: UsageTrackerProtocol = UsageTracker.shared,
                subscriptionStore: SubscriptionStoreProtocol? = nil) {
        self.apiClient = apiClient
        self.store = store
        self.tokenStore = tokenStore
        self.background = background
        self.orchestrator = orchestrator
        self.repository = UploadJobRepository(store: store)
        self.usageTracker = usageTracker
        self.subscriptionStore = subscriptionStore
    }

    public func enqueue(stagedURL: URL,
                        contentType: String,
                        originalFilename: String?,
                        retentionPolicy: RetentionPolicy = .default) async throws -> UploadJob {
        try await enqueue(stagedURL: stagedURL,
                          contentType: contentType,
                          originalFilename: originalFilename,
                          retentionPolicy: retentionPolicy,
                          prepareObserver: nil)
    }

    /// Overload that emits `UploadPreparePhase` events to `prepareObserver`
    /// during the pre-R2-PUT window (hash + presign + multipart-init) and
    /// around the POST /complete finalize. Share-ext uses it to keep the UI
    /// alive during the 10-15s pause that used to show a frozen 0% bar.
    public func enqueue(stagedURL: URL,
                        contentType: String,
                        originalFilename: String?,
                        retentionPolicy: RetentionPolicy = .default,
                        prepareObserver: (@Sendable (UploadPreparePhase) -> Void)?) async throws -> UploadJob {
        _ = try await ensureDeviceToken()
        let attrs = try FileManager.default.attributesOfItem(atPath: stagedURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let relative = try relativePath(for: stagedURL)

        // Pre-flight: daily cap / file size / retention caps. Throws typed
        // `SubscriptionGate` errors the UI translates into paywall triggers.
        try await preflightQuotaAndCaps(size: size, retention: retentionPolicy)

        var job = UploadJob(contentType: contentType,
                            sizeBytes: size,
                            originalFilename: originalFilename,
                            stagedRelativePath: relative,
                            retentionPolicy: retentionPolicy)
        try await repository.create(job)
        let clientJobId = job.clientJobId
        await MainActor.run {
            UploadProgressMonitor.shared.start(
                clientJobId: clientJobId,
                filename: originalFilename ?? "",
                contentType: contentType,
                bytesTotal: size,
                stage: .hashing
            )
        }

        do {
            try await repository.updateStatus(clientJobId: clientJobId, status: .presigning)
            // Emit hashing immediately so the UI swaps "Preparing…" → determinate bar.
            prepareObserver?(.hashing(bytesHashed: 0, totalBytes: size))
            // Hash and presign run concurrently; sha256 is sent at /complete.
            // Trade: first upload of a new hash skips server-side dedup fast-path.
            async let hashFuture = SHA256Streamer.hash(fileAt: stagedURL, progress: { bytes in
                prepareObserver?(.hashing(bytesHashed: bytes, totalBytes: size))
                Task { @MainActor in
                    UploadProgressMonitor.shared.updateProgress(
                        clientJobId: clientJobId,
                        progress: size > 0 ? Double(bytes) / Double(size) : 1,
                        bytesSent: bytes,
                        bytesTotal: size,
                        stage: .hashing
                    )
                }
            })
            // Presign races alongside hash. Keep the tray monitor on hashing
            // progress until the local file pass is done; otherwise large files
            // look stuck on an indeterminate "creating link" state.
            async let presignFuture = apiClient.requestUpload(PresignRequest(
                clientJobId: clientJobId,
                contentType: contentType,
                sizeBytes: size,
                sha256: nil,
                originalFilename: originalFilename,
                retentionPolicy: retentionPolicy.rawValue,
                customTtlSeconds: nil
            ))
            let sha = try await hashFuture
            prepareObserver?(.presigning)
            await MainActor.run {
                UploadProgressMonitor.shared.updateStage(
                    clientJobId: clientJobId,
                    stage: .presigning,
                    progress: 1,
                    bytesSent: size,
                    bytesTotal: size
                )
            }
            let presign = try await presignFuture
            job.sha256 = sha
            try await repository.setSha256(clientJobId: clientJobId, sha256: sha)

            // WHY: the dedup response is disjoint from the happy path — it carries no
            // uploadId or upload instruction, so short-circuit before touching those.
            if let dedupe = presign.deduped {
                try await orchestrator.recordDedupe(clientJobId: clientJobId,
                                                    dedupe: dedupe,
                                                    contentType: contentType,
                                                    sizeBytes: size,
                                                    filename: originalFilename)
                job.status = .deduped
                job.shortURL = dedupe.shortUrl
                job.remoteAssetId = dedupe.assetId.uuidString
                job.expiresAt = dedupe.expiresAt
                job.deleteAfter = dedupe.deleteAfter
                return job
            }

            guard let uploadId = presign.uploadId, let instruction = presign.upload else {
                throw APIError.decoding(underlying: "presign response missing uploadId or upload instruction")
            }
            try await repository.setPresign(clientJobId: clientJobId,
                                            uploadId: uploadId)

            // Tier 1: copy the optimistic shortUrl immediately so clipboard
            // lands before bytes do. Banner/Live Activity markers below.
            if let shortUrl = presign.shortUrl {
                await orchestrator.recordPendingLink(clientJobId: clientJobId,
                                                     token: presign.token ?? "",
                                                     shortUrl: shortUrl)
                job.shortURL = shortUrl
                job.linkAlreadyCopied = true
            }

            try await repository.updateStatus(clientJobId: clientJobId, status: .uploading)
            await MainActor.run {
                UploadProgressMonitor.shared.updateStage(
                    clientJobId: clientJobId,
                    stage: .uploading,
                    progress: 0,
                    bytesSent: 0,
                    bytesTotal: size
                )
            }

            let bannerShortUrl = presign.shortUrl?.absoluteString
            await MainActor.run {
                if let url = bannerShortUrl {
                    UploadProgressMonitor.shared.markLinkReady(clientJobId: clientJobId,
                                                                shortUrl: url)
                }
            }
            await LiveActivityController.shared.startOrDefer(
                clientJobId: clientJobId,
                filename: originalFilename ?? "",
                contentType: contentType,
                retentionPolicy: retentionPolicy.rawValue,
                bytesTotal: size
            )

            switch instruction {
            case .single(let single):
                try background.scheduleUpload(job: job, upload: single, fileURL: stagedURL)
            case .multipart(let multipart):
                // Tier 2: parallel part upload via foreground URLSession. The
                // uploader finalizes /complete itself once all parts land.
                try await scheduleMultipart(job: job,
                                            uploadId: uploadId,
                                            plan: multipart,
                                            stagedURL: stagedURL,
                                            size: size,
                                            contentType: contentType,
                                            originalFilename: originalFilename,
                                            sha256: sha,
                                            prepareObserver: prepareObserver)
            }
            job.status = .uploading
            job.expiresAt = presign.expiresAt
            job.deleteAfter = presign.deleteAfter
            return job
        } catch {
            try? await repository.markFailed(clientJobId: clientJobId, error: error.localizedDescription)
            await MainActor.run {
                UploadProgressMonitor.shared.finishFailure(clientJobId: clientJobId,
                                                           reason: error.localizedDescription)
            }
            throw error
        }
    }

    public func enqueueDrop(urls: [URL], retentionPolicy: RetentionPolicy = .default) async throws -> EnqueueResult {
        try await enqueueDrop(urls: urls, retentionPolicy: retentionPolicy, progressClientJobId: nil)
    }

    public func enqueueDrop(urls: [URL],
                            retentionPolicy: RetentionPolicy = .default,
                            progressClientJobId: UUID?) async throws -> EnqueueResult {
        let stagingTotalBytes = urls.map(Self.fileSize).reduce(0, +)
        var stagedBytesBase: Int64 = 0

        func stagingProgress(for url: URL) -> (@Sendable (_ copied: Int64, _ total: Int64) -> Void)? {
            guard let progressClientJobId else { return nil }
            let base = stagedBytesBase
            let fallbackTotal = Self.fileSize(for: url)
            return { copied, total in
                let effectiveTotal = max(1, stagingTotalBytes)
                let reportedCopied = total == 0 && copied == 0 ? fallbackTotal : copied
                let effectiveCopied = min(effectiveTotal, base + reportedCopied)
                Task { @MainActor in
                    UploadProgressMonitor.shared.updateProgress(
                        clientJobId: progressClientJobId,
                        progress: Double(effectiveCopied) / Double(effectiveTotal),
                        bytesSent: effectiveCopied,
                        bytesTotal: stagingTotalBytes,
                        stage: .staging
                    )
                }
            }
        }

        if urls.count == 1 {
            let source = urls[0]
            let staged = try stageDroppedURL(source, progress: stagingProgress(for: source))
            let job = try await enqueue(stagedURL: staged.url,
                                        contentType: staged.contentType,
                                        originalFilename: staged.filename,
                                        retentionPolicy: retentionPolicy)
            return .single(job)
        }
        var staged: [StagedDrop] = []
        for url in urls {
            let stagedItem = try stageDroppedURL(url, progress: stagingProgress(for: url))
            staged.append(stagedItem)
            stagedBytesBase += Self.fileSize(for: url)
        }
        let bundle = try await enqueueBundle(stagedItems: staged,
                                             retentionPolicy: retentionPolicy,
                                             progressClientJobId: progressClientJobId)
        return .bundle(bundle)
    }

    /// Stages a user-provided URL into the App Group staging dir and resolves
    /// MIME / filename. Extracted so single + bundle drop paths share one
    /// security-scope dance and one MIME inference.
    private func stageDroppedURL(_ url: URL,
                                 progress: (@Sendable (_ copied: Int64, _ total: Int64) -> Void)? = nil) throws -> StagedDrop {
        // WHY: SwiftUI's `fileImporter` and UIDocumentPicker hand back
        // security-scoped URLs — sandboxed Release builds (TestFlight / App
        // Store) silently refuse reads outside an active scope. Harmless on
        // non-scoped inputs (returns `false` and the defer no-ops).
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        let stagingRoot = try AppGroupPaths.stagingDirectory()
        let filename = url.lastPathComponent
        let destination = stagingRoot.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
        try Self.copyDroppedFile(from: url, to: destination, progress: progress)
        let ct = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return StagedDrop(url: destination, filename: filename, contentType: ct)
    }

    private static func copyDroppedFile(from source: URL,
                                        to destination: URL,
                                        progress: (@Sendable (_ copied: Int64, _ total: Int64) -> Void)?) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        let resourceValues = try source.resourceValues(forKeys: [.isDirectoryKey])
        guard resourceValues.isDirectory != true else {
            try fileManager.copyItem(at: source, to: destination)
            progress?(1, 1)
            return
        }

        let total = fileSize(for: source)
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        var copied: Int64 = 0
        while true {
            let chunk = try input.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            try output.write(contentsOf: chunk)
            copied += Int64(chunk.count)
            progress?(copied, total)
        }
        progress?(copied, total)
    }

    private static func fileSize(for url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private struct StagedDrop {
        let url: URL
        let filename: String
        let contentType: String
    }

    /// Bundle entry point: hash + size + presign in one batch round-trip, then
    /// fan out PUT R2 in parallel and `/complete` per item. Returns a
    /// `BundleUploadJob` whose `aggregateProgress` stream the UI consumes for
    /// the headline "Sending N files · X%". The actual /complete + history
    /// persistence is delegated to `UploadOrchestrator.recordBundleSuccess`
    /// once the last per-item /complete returns.
    public func enqueueBundle(stagedURLs: [URL], retentionPolicy: RetentionPolicy) async throws -> BundleUploadJob {
        let staged = stagedURLs.map { url -> StagedDrop in
            // Files at this entry point are already inside the App Group
            // staging dir (caller's responsibility), so we skip the
            // copy-to-staging dance — but still infer mime from the extension.
            let filename = url.lastPathComponent
            let ct = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            return StagedDrop(url: url, filename: filename, contentType: ct)
        }
        return try await enqueueBundle(stagedItems: staged, retentionPolicy: retentionPolicy)
    }

    private func enqueueBundle(stagedItems: [StagedDrop],
                               retentionPolicy: RetentionPolicy,
                               progressClientJobId: UUID? = nil) async throws -> BundleUploadJob {
        _ = try await ensureDeviceToken()

        // 1. Per-file metadata + sha256 in parallel — server batch handler
        // accepts optional sha256 (lets it dedup early on the fast path).
        var metas: [ItemMeta] = []
        let hashTotalBytes = stagedItems.map { Self.fileSize(for: $0.url) }.reduce(0, +)
        let prepareAggregator = progressClientJobId.map {
            PreparationProgressAggregator(monitorClientJobId: $0,
                                          totalBytes: hashTotalBytes,
                                          stage: .hashing)
        }
        try await withThrowingTaskGroup(of: ItemMeta.self) { group in
            for staged in stagedItems {
                let relative = try self.relativePath(for: staged.url)
                let attrs = try FileManager.default.attributesOfItem(atPath: staged.url.path)
                let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                let clientJobId = UUID()
                group.addTask {
                    let sha = try await SHA256Streamer.hash(fileAt: staged.url, progress: { bytes in
                        if let prepareAggregator {
                            Task { await prepareAggregator.update(itemId: clientJobId, bytes: bytes) }
                        }
                    })
                    return ItemMeta(staged: staged,
                                    size: size,
                                    sha256: sha,
                                    clientJobId: clientJobId,
                                    stagedRelative: relative)
                }
            }
            for try await meta in group { metas.append(meta) }
        }
        // Stable order by clientJobId so the response items[] line-up is
        // deterministic in tests; backend keys by clientJobId regardless.
        metas.sort { $0.clientJobId.uuidString < $1.clientJobId.uuidString }

        // 2. Preflight: total payload size + per-file caps (the daily-cap
        // gate runs server-side over `items.length` atomically, so we only
        // enforce per-file size + retention locally for early UX feedback).
        for meta in metas {
            try await preflightQuotaAndCaps(size: meta.size, retention: retentionPolicy)
        }

        // 3. One presign batch round-trip.
        let batchItems = metas.map {
            BatchUploadItemRequest(clientJobId: $0.clientJobId.uuidString,
                                   contentType: $0.staged.contentType,
                                   sizeBytes: $0.size,
                                   sha256: $0.sha256,
                                   originalFilename: $0.staged.filename)
        }
        // WHY hardcoded "signed": backend's batch endpoint accepts only
        // public|signed|password (mirrors short-link auth model). Unlisted is
        // a client-side concept; signed is the safest default for new bundles.
        if let progressClientJobId {
            await MainActor.run {
                UploadProgressMonitor.shared.updateStage(
                    clientJobId: progressClientJobId,
                    stage: .presigning,
                    progress: 1,
                    bytesSent: hashTotalBytes,
                    bytesTotal: hashTotalBytes
                )
            }
        }
        let response = try await apiClient.requestBatchUpload(BatchPresignRequest(
            retentionPolicy: retentionPolicy.rawValue,
            visibility: "signed",
            items: batchItems
        ))

        // 4. Build local UploadJob rows mirroring backend upload_job ids,
        // then PUT bytes in parallel. We don't go through the background
        // scheduler — bundles are a foreground-blocking flow with their own
        // /complete dispatch, and reusing the BG session would serialize PUTs.
        let totalBytes = metas.map(\.size).reduce(0, +)
        var continuationOpt: AsyncStream<Double>.Continuation?
        let stream = AsyncStream<Double> { continuationOpt = $0 }
        guard let continuation = continuationOpt else {
            throw APIError.transport(underlying: "failed to wire bundle progress stream")
        }

        var jobs: [UploadJob] = []
        for item in response.items {
            guard let meta = metas.first(where: { $0.clientJobId.uuidString == item.clientJobId }) else { continue }
            let job = UploadJob(clientJobId: meta.clientJobId,
                                status: .uploading,
                                contentType: meta.staged.contentType,
                                sizeBytes: meta.size,
                                sha256: meta.sha256,
                                originalFilename: meta.staged.filename,
                                remoteUploadId: item.uploadId,
                                stagedRelativePath: meta.stagedRelative,
                                retentionPolicy: retentionPolicy,
                                expiresAt: response.expiresAt,
                                deleteAfter: response.deleteAfter)
            try await repository.create(job)
            try await repository.setPresign(clientJobId: job.clientJobId, uploadId: item.uploadId)
            jobs.append(job)
        }

        let monitorClientJobId = jobs.first?.clientJobId ?? UUID()
        let monitorFilename = "\(jobs.count) files"

        // Snapshot bundle values outside the actor closure so progress ticks
        // don't capture `self` (which would force the closure non-Sendable).
        let bundleTokenForTick = response.bundleToken
        let totalBytesForTick = totalBytes
        let aggregator = BundleProgressAggregator(
            totalBytes: totalBytes,
            continuation: continuation,
            onTick: { bytes, fraction in
                Task {
                    await LiveActivityController.shared.updateBundleProgress(
                        bundleToken: bundleTokenForTick,
                        bytesUploaded: bytes,
                        totalBytes: totalBytesForTick,
                        progress: fraction
                    )
                }
                Task { @MainActor in
                    UploadProgressMonitor.shared.updateProgress(
                        clientJobId: monitorClientJobId,
                        progress: fraction,
                        bytesSent: bytes,
                        bytesTotal: totalBytesForTick
                    )
                }
            }
        )

        let bundleShortUrl = response.bundleShortUrl
        let bundleToken = response.bundleToken

        // 5. Fan out PUT R2 + /complete per item, collect completed assets.
        let bundleJob = BundleUploadJob(bundleToken: bundleToken,
                                        bundleShortUrl: bundleShortUrl,
                                        jobs: jobs,
                                        totalBytes: totalBytes,
                                        aggregateProgress: stream)

        await MainActor.run {
            UploadProgressMonitor.shared.start(
                clientJobId: monitorClientJobId,
                filename: monitorFilename,
                contentType: "application/x-bundle",
                bytesTotal: totalBytes,
                stage: .uploading
            )
        }

        // Single source of truth for bundle Live Activity start. Same
        // `startOrDefer` rationale as single uploads — share ext can't render
        // the Activity, so the request is parked for the main app to drain.
        await LiveActivityController.shared.startBundleOrDefer(
            bundleToken: bundleToken,
            fileCount: metas.count,
            totalBytes: totalBytes,
            // Cap at 5 names so the activity payload stays well under Apple's
            // ~4 KB content limit; the widget shows "+(N-3) more" anyway.
            filenames: Array(metas.prefix(5).map { $0.staged.filename }),
            retentionPolicy: retentionPolicy.rawValue
        )

        // Detach so the caller can return immediately with the bundle handle
        // and watch `aggregateProgress` while uploads run in the background.
        let api = apiClient
        let orch = orchestrator
        Task { [aggregator] in
            await self.runBundleUploads(items: response.items,
                                        metas: metas,
                                        aggregator: aggregator,
                                        bundleJob: bundleJob,
                                        monitorClientJobId: monitorClientJobId,
                                        api: api,
                                        orchestrator: orch)
        }
        return bundleJob
    }

    private func runBundleUploads(items: [BatchPresignItem],
                                  metas: [ItemMeta],
                                  aggregator: BundleProgressAggregator,
                                  bundleJob: BundleUploadJob,
                                  monitorClientJobId: UUID,
                                  api: APIClientProtocol,
                                  orchestrator: UploadOrchestrator) async {
        // WHY: collect successes; on any failure abort multipart + mark job
        // failed but let other parallel uploads finish (best-effort bundle
        // recovery). The backend's pending bundle cleanup sweeps stragglers.
        let session = background.multipartURLSession
        var completed: [BundleCompletedAsset] = []
        await withTaskGroup(of: BundleCompletedAsset?.self) { group in
            for item in items {
                guard let meta = metas.first(where: { $0.clientJobId.uuidString == item.clientJobId }) else { continue }
                group.addTask { [repository, log] in
                    do {
                        let multi: CompleteRequest.MultipartCompletion?
                        switch item.upload {
                        case .single(let single):
                            try await Self.putR2Single(session: session,
                                                       url: single.url,
                                                       headers: single.headers,
                                                       method: single.method,
                                                       fileURL: meta.staged.url,
                                                       totalBytes: meta.size,
                                                       jobId: meta.clientJobId,
                                                       aggregator: aggregator)
                            multi = nil
                        case .multipart(let plan):
                            // Reuse MultipartUploader for parallel part PUTs;
                            // aggregator sums fractions across all parts.
                            let uploader = MultipartUploader(session: session)
                            let uPlan = MultipartUploader.Plan(
                                multipartUploadId: plan.multipartUploadId,
                                partSize: plan.partSize,
                                parts: plan.parts.map { .init(partNumber: $0.partNumber, url: $0.url) }
                            )
                            let result = try await uploader.upload(
                                fileURL: meta.staged.url,
                                fileSize: meta.size,
                                plan: uPlan,
                                progress: { fraction in
                                    let bytes = Int64(Double(meta.size) * fraction)
                                    Task { await aggregator.update(jobId: meta.clientJobId, bytes: bytes) }
                                }
                            )
                            multi = CompleteRequest.MultipartCompletion(
                                parts: result.parts.map { .init(partNumber: $0.partNumber, eTag: $0.eTag) }
                            )
                        }
                        let resp = try await api.completeUpload(
                            uploadId: item.uploadId,
                            request: CompleteRequest(contentType: meta.staged.contentType,
                                                     sizeBytes: meta.size,
                                                     sha256: meta.sha256,
                                                     originalFilename: meta.staged.filename,
                                                     multipart: multi)
                        )
                        try await repository.markCompleted(clientJobId: meta.clientJobId,
                                                           assetId: resp.assetId,
                                                           shortURL: resp.shortUrl,
                                                           expiresAt: resp.expiresAt,
                                                           deleteAfter: resp.deleteAfter)
                        await aggregator.update(jobId: meta.clientJobId, bytes: meta.size)
                        return BundleCompletedAsset(assetId: resp.assetId,
                                                    filename: meta.staged.filename,
                                                    sizeBytes: meta.size,
                                                    contentType: meta.staged.contentType)
                    } catch {
                        log.error("bundle item upload failed: \(error.localizedDescription, privacy: .public)")
                        try? await repository.markFailed(clientJobId: meta.clientJobId,
                                                        error: error.localizedDescription)
                        return nil
                    }
                }
            }
            for await maybe in group {
                if let asset = maybe { completed.append(asset) }
            }
        }
        await aggregator.finish()
        if completed.count == items.count {
            await orchestrator.recordBundleSuccess(bundle: bundleJob, completedAssets: completed)
            await MainActor.run {
                UploadProgressMonitor.shared.finishSuccess(
                    clientJobId: monitorClientJobId,
                    shortUrl: bundleJob.bundleShortUrl.absoluteString
                )
            }
        } else {
            let failedCount = max(1, items.count - completed.count)
            await MainActor.run {
                UploadProgressMonitor.shared.finishFailure(
                    clientJobId: monitorClientJobId,
                    reason: "\(failedCount) file\(failedCount == 1 ? "" : "s") failed"
                )
            }
        }
    }

    /// Single-PUT R2 upload with per-byte progress wired into the bundle
    /// aggregator. Uses a foreground URLSession (background session would
    /// serialize). No retry — errors bubble; bundle aggregator finishes via
    /// caller's task group.
    private static func putR2Single(session: URLSession,
                                    url: URL,
                                    headers: [String: String],
                                    method: String,
                                    fileURL: URL,
                                    totalBytes: Int64,
                                    jobId: UUID,
                                    aggregator: BundleProgressAggregator) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased()
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (_, response) = try await session.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.http(status: status, problem: nil)
        }
        // URLSession.upload(for:fromFile:) doesn't expose progress callbacks
        // without a delegate, so we count the file as fully uploaded on
        // success. For sub-100MB items this lands within seconds; for larger
        // items the multipart branch supplies fine-grained progress.
        await aggregator.update(jobId: jobId, bytes: totalBytes)
    }

    private struct ItemMeta: Sendable {
        let staged: StagedDrop
        let size: Int64
        let sha256: String
        let clientJobId: UUID
        let stagedRelative: String
    }

    /// Pre-flight quota + caps check. Runs before any network work so
    /// partially-staged files don't leak on refusal. All failures are surfaced
    /// as typed `SubscriptionGate` errors so every UI caller (main app,
    /// share ext, App Intent) can map them to a consistent paywall trigger.
    private func preflightQuotaAndCaps(size: Int64, retention: RetentionPolicy) async throws {
        // Resolve the effective caps from the subscription snapshot if
        // injected; otherwise fall back to Free. WHY fallback to Free: absent
        // the locator, we're definitively outside the logged-in path — the
        // safe default is the most restrictive one.
        let caps: TierCaps
        let tier: Tier
        if let store = subscriptionStore {
            let snapshot = await store.currentSnapshot()
            caps = snapshot.caps
            tier = snapshot.isPro ? .pro(snapshot.tier ?? .monthly) : .free
        } else {
            caps = .free
            tier = .free
        }

        if size > caps.maxFileSizeBytes {
            throw SubscriptionGate.fileTooLarge(sizeBytes: size, cap: caps.maxFileSizeBytes)
        }
        if retention.ttlSeconds > caps.maxRetentionSeconds {
            throw SubscriptionGate.retentionTooLong(requestedSeconds: retention.ttlSeconds,
                                                    cap: caps.maxRetentionSeconds)
        }
        if let cap = caps.dailyUploadLimit {
            let used = await usageTracker.currentCount()
            if used >= cap {
                throw SubscriptionGate.dailyCapReached(used: used, cap: cap)
            }
        }
        _ = tier // reserved for future analytics
    }

    /// Tier 2: orchestrates the multipart upload end-to-end. Uses a foreground
    /// `URLSession` on `BackgroundSessionManager.multipartURLSession` (the
    /// background session serializes per-task and would defeat parallelism).
    /// On failure, calls the backend's abort endpoint so R2 doesn't hoard
    /// incomplete parts for 24h and the recipient's "uploading…" page stops
    /// polling.
    ///
    /// Trade-off: the multipart path pauses when the app is backgrounded
    /// mid-upload. For files up to ~100 MB that's inside iOS's ~30s grace.
    /// Resume state across kills is an explicit follow-up (persist part
    /// ETags to SwiftData) — not in Tier 2 scope.
    private func scheduleMultipart(job: UploadJob,
                                   uploadId: String,
                                   plan: UploadInstruction.MultipartInstruction,
                                   stagedURL: URL,
                                   size: Int64,
                                   contentType: String,
                                   originalFilename: String?,
                                   sha256: String,
                                   prepareObserver: (@Sendable (UploadPreparePhase) -> Void)? = nil) async throws {
        let uploader = MultipartUploader(session: background.multipartURLSession)
        let uploaderPlan = MultipartUploader.Plan(
            multipartUploadId: plan.multipartUploadId,
            partSize: plan.partSize,
            parts: plan.parts.map { .init(partNumber: $0.partNumber, url: $0.url) }
        )
        let clientJobId = job.clientJobId
        let bytesTotal = size
        let repo = repository
        do {
            let completion = try await uploader.upload(
                fileURL: stagedURL,
                fileSize: size,
                plan: uploaderPlan,
                progress: { fraction in
                    let bytesSent = Int64(Double(bytesTotal) * fraction)
                    Task { @MainActor in
                        UploadProgressMonitor.shared.updateProgress(clientJobId: clientJobId,
                                                                    progress: fraction,
                                                                    bytesSent: bytesSent,
                                                                    bytesTotal: bytesTotal)
                    }
                    Task {
                        await LiveActivityController.shared.updateProgress(clientJobId: clientJobId,
                                                                           progress: fraction,
                                                                           bytesSent: bytesSent,
                                                                           bytesTotal: bytesTotal)
                    }
                    Task.detached(priority: .utility) {
                        try? await repo.updateProgress(clientJobId: clientJobId,
                                                       progress: fraction)
                    }
                }
            )
            let multipartPayload = CompleteRequest.MultipartCompletion(
                parts: completion.parts.map { .init(partNumber: $0.partNumber, eTag: $0.eTag) }
            )
            try await repository.updateStatus(clientJobId: clientJobId, status: .completing)
            prepareObserver?(.finalizing)
            await MainActor.run {
                UploadProgressMonitor.shared.updateStage(
                    clientJobId: clientJobId,
                    stage: .finalizing,
                    progress: 1,
                    bytesSent: bytesTotal,
                    bytesTotal: bytesTotal
                )
            }
            let response = try await apiClient.completeUpload(
                uploadId: uploadId,
                request: CompleteRequest(contentType: contentType,
                                         sizeBytes: size,
                                         sha256: sha256,
                                         originalFilename: originalFilename,
                                         multipart: multipartPayload)
            )
            await orchestrator.handleMultipartCompletion(
                clientJobId: clientJobId,
                completion: response,
                contentType: contentType,
                sizeBytes: size,
                filename: originalFilename
            )
        } catch {
            log.error("multipart upload failed; aborting: \(error.localizedDescription, privacy: .public)")
            try? await apiClient.abortMultipartUpload(uploadId: uploadId)
            await orchestrator.handleTaskFailure(clientJobId: clientJobId, error: error)
            throw error
        }
    }

    private func ensureDeviceToken() async throws -> DeviceToken {
        if let existing = try await tokenStore.load() { return existing }
        let platform: String
        #if os(iOS)
        platform = "ios"
        #elseif os(macOS)
        platform = "macos"
        #else
        platform = "unknown"
        #endif
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let token = try await apiClient.registerDevice(platform: platform, appVersion: version)
        try await tokenStore.save(token)
        return token
    }

    private func relativePath(for url: URL) throws -> String {
        let root = try AppGroupPaths.containerURL()
        let rootPath = root.standardizedFileURL.path
        let absolute = url.standardizedFileURL.path
        if absolute.hasPrefix(rootPath) {
            return String(absolute.dropFirst(rootPath.count))
        }
        return absolute
    }
}
