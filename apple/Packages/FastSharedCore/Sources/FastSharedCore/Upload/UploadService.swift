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
            let sha = try await SHA256Streamer.hash(fileAt: stagedURL)
            job.sha256 = sha
            let request = PresignRequest(clientJobId: job.clientJobId,
                                         contentType: contentType,
                                         sizeBytes: size,
                                         sha256: sha,
                                         originalFilename: originalFilename,
                                         retentionPolicy: retentionPolicy.rawValue,
                                         customTtlSeconds: nil)
            let presign = try await apiClient.requestUpload(request)

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

            try await repository.updateStatus(clientJobId: job.clientJobId, status: .uploading)
            try background.scheduleUpload(job: job, upload: instruction, fileURL: stagedURL)
            job.status = .uploading
            job.expiresAt = presign.expiresAt
            job.deleteAfter = presign.deleteAfter
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
