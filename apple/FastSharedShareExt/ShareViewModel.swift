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
    case uploading(progress: Double, bytesSent: Int64, bytesTotal: Int64)
    case success(link: FastSharedCore.ShareLink, filename: String, deduped: Bool)
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

    func startObserving(clientJobId: UUID, filename: String, totalBytes: Int64) {
        pollTask?.cancel()
        activeJobId = clientJobId
        phase = .preparing

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
            phase = .preparing
        case .uploading:
            let bytesSent = Int64(Double(totalBytes) * snapshot.progress)
            phase = .uploading(progress: snapshot.progress, bytesSent: bytesSent, bytesTotal: totalBytes)
        case .completing:
            // Server-side finalizing — keep progress bar at 100% rather than snapping back.
            phase = .uploading(progress: 1.0, bytesSent: totalBytes, bytesTotal: totalBytes)
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
