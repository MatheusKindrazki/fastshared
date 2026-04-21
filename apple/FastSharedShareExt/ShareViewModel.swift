import Foundation
import Observation
import FastSharedCore

public struct StagedItem: Identifiable, Sendable {
    public let id: UUID
    public let localURL: URL
    public let contentType: String
    public let sizeBytes: Int64
    public let filename: String

    public init(id: UUID = UUID(),
                localURL: URL,
                contentType: String,
                sizeBytes: Int64,
                filename: String) {
        self.id = id
        self.localURL = localURL
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.filename = filename
    }
}

/// Represents every UI state the share extension can be in. The view binds to this enum and only this enum.
enum ShareUploadPhase: Sendable {
    case idle
    case preparing
    /// Pre-presign hash pass. Determinate bar when `totalBytes` known.
    /// Exists so a 125 MB video doesn't freeze the UI at 0% for ~4s while
    /// SHA-256 streams the file.
    case hashing(bytesHashed: Int64, totalBytes: Int64)
    /// Presign (and multipart init for >10 MB) round-trip. Indeterminate.
    case presigning
    case uploading(progress: Double, bytesSent: Int64, bytesTotal: Int64)
    /// M4: aggregated bundle progress (N>1 files). Single uploads stay on
    /// `.uploading`/`.success`. Drives the "Sending {N} files · {bytes}" headline.
    case uploadingBundle(fileCount: Int, progress: Double, bytesUploaded: Int64, totalBytes: Int64)
    /// POST /complete in flight (multipart path only — single-PUT finalize
    /// happens in the background session after the extension closes).
    case finalizing
    case success(link: FastSharedCore.ShareLink, filename: String, deduped: Bool)
    /// M4: bundle finished — short URL is already on the clipboard (orchestrator
    /// did the copy). UI shows a celebratory headline + count.
    case bundleSuccess(fileCount: Int, shortUrl: URL)
    case failed(reason: String, requestId: String)
}

@Observable
@MainActor
final class ShareViewModel {
    var items: [StagedItem] = []
    var phase: ShareUploadPhase = .idle
    var retentionPolicy: RetentionPolicy

    /// True once "Done" has been tapped or the extension is ready to dismiss. The view controller observes this.
    var readyToDismiss: Bool = false

    /// True once the user explicitly cancelled the extension from the UI.
    var cancelled: Bool = false

    private var pollTask: Task<Void, Never>?
    private var activeJobId: UUID?

    init() {
        // WHY: honor the default picked in the main app's Settings; fall back to the global default if unset.
        let defaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
        let stored = defaults?.string(forKey: "default_retention_policy")
        self.retentionPolicy = stored.flatMap(RetentionPolicy.init(rawValue:)) ?? .default
    }

    /// Mirrors a `UploadPreparePhase` emission from UploadService into the UI.
    /// Called synchronously on MainActor from the share extension's upload
    /// callback before the SwiftData status poll sees anything.
    func applyPreparePhase(_ phase: FastSharedCore.UploadPreparePhase) {
        // Ignore once we've reached a terminal state to avoid a late observer
        // emission flashing back to hashing/presigning after success/failure.
        switch self.phase {
        case .success, .bundleSuccess, .failed: return
        default: break
        }
        switch phase {
        case .hashing(let done, let total):
            self.phase = .hashing(bytesHashed: done, totalBytes: total)
        case .presigning:
            self.phase = .presigning
        case .finalizing:
            self.phase = .finalizing
        }
    }

    func startObserving(clientJobId: UUID, filename: String, totalBytes: Int64) {
        pollTask?.cancel()
        activeJobId = clientJobId
        // Don't clobber a more-specific prepare phase the observer already set.
        if case .hashing = phase {} else if case .presigning = phase {} else if case .finalizing = phase {} else if case .uploading = phase {} else {
            phase = .preparing
        }

        let repo = UploadJobRepository(store: SwiftDataStore.shared)
        pollTask = Task { @MainActor [weak self] in
            // WHY: a 150ms polling cadence is cheap inside an extension that lives for at most ~30s, and avoids
            // wiring SwiftData change notifications through an actor boundary. Replace with an AsyncStream-backed
            // observer if/when SwiftData exposes a clean watch API.
            while !Task.isCancelled {
                guard let self else { return }
                let snapshot = try? await repo.snapshot(clientJobId: clientJobId)
                if let snapshot {
                    let shareLink = try? await repo.findShareLinkForJob(clientJobId: clientJobId)
                    self.apply(snapshot: snapshot, shareLink: shareLink, filename: filename, totalBytes: totalBytes)
                    if case .success = self.phase { return }
                    if case .failed = self.phase { return }
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    /// Bundle counterpart of `startObserving`. Consumes the aggregator stream
    /// from `BundleUploadJob` so the headline ("Sending N files · X / Y") and
    /// progress bar update in real time. Calls `onComplete` when the stream
    /// finishes (1.0); the caller resolves into `.bundleSuccess`.
    func startObservingBundle(bundle: BundleUploadJob,
                              onComplete: @escaping () -> Void) {
        pollTask?.cancel()
        let fileCount = bundle.jobs.count
        let totalBytes = bundle.totalBytes
        phase = .uploadingBundle(fileCount: fileCount,
                                 progress: 0,
                                 bytesUploaded: 0,
                                 totalBytes: totalBytes)
        pollTask = Task { @MainActor [weak self] in
            for await fraction in bundle.aggregateProgress {
                guard let self else { return }
                let bytes = Int64(Double(totalBytes) * max(0, min(1, fraction)))
                self.phase = .uploadingBundle(fileCount: fileCount,
                                              progress: fraction,
                                              bytesUploaded: bytes,
                                              totalBytes: totalBytes)
            }
            // Stream finished — orchestrator has copied bundleShortUrl by now.
            onComplete()
        }
    }

    /// Flips the view into `.bundleSuccess`. Caller (controller) invokes after
    /// the aggregator stream finishes; orchestrator already wrote the local
    /// history row + clipboard.
    func reportBundleSuccess(fileCount: Int, shortUrl: URL) {
        phase = .bundleSuccess(fileCount: fileCount, shortUrl: shortUrl)
    }

    func reportEnqueueFailure(error: Error, requestId: UUID) {
        pollTask?.cancel()
        let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        phase = .failed(reason: reason, requestId: String(requestId.uuidString.prefix(8)))
    }

    func finishForDismissal() {
        pollTask?.cancel()
        readyToDismiss = true
    }

    func cancel() {
        pollTask?.cancel()
        cancelled = true
    }

    private func apply(snapshot: UploadJob, shareLink: FastSharedCore.ShareLink?, filename: String, totalBytes: Int64) {
        switch snapshot.status {
        case .queued, .presigning:
            if case .success = phase { return }
            if case .failed = phase { return }
            // Prefer the finer-grained prepare phases the UploadService
            // observer already set; `.presigning` status in SwiftData is a
            // coarser label than the observer's `hashing`/`presigning`.
            if case .hashing = phase { return }
            if case .presigning = phase { return }
            if case .uploading = phase { return }
            phase = .preparing
        case .uploading:
            let bytesSent = Int64(Double(totalBytes) * snapshot.progress)
            phase = .uploading(progress: snapshot.progress, bytesSent: bytesSent, bytesTotal: totalBytes)
        case .completing:
            // Server-side finalizing — show the finalizing label so users
            // aren't staring at a frozen 100% bar during the /complete RTT.
            phase = .finalizing
        case .completed:
            if let link = shareLink {
                phase = .success(link: link, filename: filename, deduped: false)
            } else {
                phase = .uploading(progress: 1.0, bytesSent: totalBytes, bytesTotal: totalBytes)
            }
        case .deduped:
            if let link = shareLink {
                phase = .success(link: link, filename: filename, deduped: true)
            }
        case .failed:
            let reason = snapshot.errorMessage ?? "Upload failed."
            let requestId = String(snapshot.clientJobId.uuidString.prefix(8))
            phase = .failed(reason: reason, requestId: requestId)
        }
    }
}
