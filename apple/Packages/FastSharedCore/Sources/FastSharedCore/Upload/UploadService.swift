import Foundation
import OSLog
import UniformTypeIdentifiers

public protocol UploadServiceProtocol: Sendable {
    func enqueue(stagedURL: URL,
                 contentType: String,
                 originalFilename: String?,
                 retentionPolicy: RetentionPolicy) async throws -> UploadJob
    func enqueueDrop(urls: [URL], retentionPolicy: RetentionPolicy) async throws -> [UploadJob]
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

    func enqueueDrop(urls: [URL]) async throws -> [UploadJob] {
        try await enqueueDrop(urls: urls, retentionPolicy: .default)
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

        do {
            try await repository.updateStatus(clientJobId: job.clientJobId, status: .presigning)
            // Hash and presign run concurrently; sha256 is sent at /complete.
            // Trade: first upload of a new hash skips server-side dedup fast-path.
            async let hashFuture = SHA256Streamer.hash(fileAt: stagedURL)
            async let presignFuture = apiClient.requestUpload(PresignRequest(
                clientJobId: job.clientJobId,
                contentType: contentType,
                sizeBytes: size,
                sha256: nil,
                originalFilename: originalFilename,
                retentionPolicy: retentionPolicy.rawValue,
                customTtlSeconds: nil
            ))
            let (sha, presign) = try await (hashFuture, presignFuture)
            job.sha256 = sha
            try await repository.setSha256(clientJobId: job.clientJobId, sha256: sha)

            // WHY: the dedup response is disjoint from the happy path — it carries no
            // uploadId or upload instruction, so short-circuit before touching those.
            if let dedupe = presign.deduped {
                try await orchestrator.recordDedupe(clientJobId: job.clientJobId,
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
            try await repository.setPresign(clientJobId: job.clientJobId,
                                            uploadId: uploadId)

            // Tier 1: copy the optimistic shortUrl immediately so clipboard
            // lands before bytes do. Banner/Live Activity markers below.
            if let shortUrl = presign.shortUrl {
                await orchestrator.recordPendingLink(clientJobId: job.clientJobId,
                                                     token: presign.token ?? "",
                                                     shortUrl: shortUrl)
                job.shortURL = shortUrl
                job.linkAlreadyCopied = true
            }

            try await repository.updateStatus(clientJobId: job.clientJobId, status: .uploading)
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
                                            sha256: sha)
            }
            job.status = .uploading
            job.expiresAt = presign.expiresAt
            job.deleteAfter = presign.deleteAfter
            // Single source of truth for Live Activity start. Every upload
            // entry path (share ext, screenshot banner, App Intents, drag-drop,
            // future file picker) lands here. `startOrDefer` routes:
            //   • main app → creates the Activity immediately.
            //   • share extension (no widget descriptors in-process) → saves
            //     the request to the App Group; `FastSharedApp.init` /
            //     `handleEventsForBackgroundURLSession` drain it when the
            //     main app wakes, so the Activity is created where it can
            //     actually render on the Dynamic Island.
            // Compiles to a no-op on non-iOS targets.
            await LiveActivityController.shared.startOrDefer(
                clientJobId: job.clientJobId,
                filename: originalFilename ?? "",
                contentType: contentType,
                retentionPolicy: retentionPolicy.rawValue,
                bytesTotal: size
            )
            // In-app banner — fallback for devices without Dynamic Island
            // and for users with Live Activities disabled in Settings.
            let bannerClientJobId = job.clientJobId
            let bannerFilename = originalFilename ?? ""
            let bannerShortUrl = presign.shortUrl?.absoluteString
            await MainActor.run {
                UploadProgressMonitor.shared.start(
                    clientJobId: bannerClientJobId,
                    filename: bannerFilename,
                    contentType: contentType,
                    bytesTotal: size
                )
                // Tier 1: after start(), tell the banner the link is already
                // copied so it swaps the headline to "Link copied — still
                // uploading".
                if let url = bannerShortUrl {
                    UploadProgressMonitor.shared.markLinkReady(clientJobId: bannerClientJobId,
                                                                shortUrl: url)
                }
            }
            return job
        } catch {
            try? await repository.markFailed(clientJobId: job.clientJobId, error: error.localizedDescription)
            throw error
        }
    }

    public func enqueueDrop(urls: [URL], retentionPolicy: RetentionPolicy = .default) async throws -> [UploadJob] {
        var jobs: [UploadJob] = []
        let stagingRoot = try AppGroupPaths.stagingDirectory()
        for url in urls {
            // WHY: SwiftUI's `fileImporter` and UIDocumentPicker hand back
            // security-scoped URLs — reading them in a sandboxed Release build
            // (TestFlight / App Store) fails silently unless we enter the scope
            // first. `startAccessingSecurityScopedResource()` returns `false` when
            // the URL isn't scoped (e.g. it came from the share extension's
            // staging path), so the call is harmless on non-scoped inputs. We
            // always pair it with `stopAccessing...` via `defer`.
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }

            let filename = url.lastPathComponent
            let destination = stagingRoot.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
            try FileManager.default.copyItem(at: url, to: destination)
            let ct = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let job = try await enqueue(stagedURL: destination,
                                        contentType: ct,
                                        originalFilename: filename,
                                        retentionPolicy: retentionPolicy)
            jobs.append(job)
        }
        return jobs
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

        let bypass = DevOverrides.unlimitedFreeCaps
        if !bypass, size > caps.maxFileSizeBytes {
            throw SubscriptionGate.fileTooLarge(sizeBytes: size, cap: caps.maxFileSizeBytes)
        }
        if !bypass, retention.ttlSeconds > caps.maxRetentionSeconds {
            throw SubscriptionGate.retentionTooLong(requestedSeconds: retention.ttlSeconds,
                                                    cap: caps.maxRetentionSeconds)
        }
        if let cap = caps.dailyUploadLimit, !bypass {
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
                                   sha256: String) async throws {
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
