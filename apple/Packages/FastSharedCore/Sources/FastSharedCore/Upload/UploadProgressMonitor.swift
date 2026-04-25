import Foundation
import Observation

/// In-app fallback for upload feedback. Mirrors `LiveActivityController`'s
/// lifecycle so the banner UI in RootView stays in sync with the Live
/// Activity, and so devices without Dynamic Island (or users with Live
/// Activities disabled in Settings) still see what's happening.
///
/// `@MainActor` placement on the class is intentional — banner state is read
/// by SwiftUI on the main thread; making the whole class MainActor avoids an
/// actor hop on every progress update. Cross-thread callers (UploadService,
/// BackgroundSessionManager, UploadOrchestrator) hop themselves with
/// `await MainActor.run { ... }`.
@Observable
@MainActor
public final class UploadProgressMonitor {
    public static let shared = UploadProgressMonitor()

    public struct ActiveUpload: Identifiable, Equatable, Sendable {
        public let id: UUID            // == clientJobId
        public let clientJobId: UUID
        public let filename: String
        public let contentType: String
        public var phase: Phase
        public var stage: Stage
        public var progress: Double    // 0.0…1.0
        public var bytesSent: Int64
        public var bytesTotal: Int64
        public var shortUrl: String?
        public var error: String?
        // Tier 1: true once the server-minted short URL is on the clipboard,
        // even if the upload itself is still in progress. Drives a copy swap
        // in the banner from "Uploading…" to "Link copied — still uploading".
        public var linkReady: Bool

        public enum Phase: String, Sendable {
            case uploading, completed, failed
        }

        public enum Stage: String, Sendable {
            case receiving
            case staging
            case hashing
            case presigning
            case uploading
            case finalizing
        }
    }

    public private(set) var current: ActiveUpload?

    private var dismissTask: Task<Void, Never>?

    private init() {}

    public func start(clientJobId: UUID,
                      filename: String,
                      contentType: String,
                      bytesTotal: Int64,
                      stage: ActiveUpload.Stage = .receiving) {
        cancelPendingDismiss()
        current = ActiveUpload(
            id: clientJobId,
            clientJobId: clientJobId,
            filename: filename,
            contentType: contentType,
            phase: .uploading,
            stage: stage,
            progress: 0,
            bytesSent: 0,
            bytesTotal: bytesTotal,
            shortUrl: nil,
            error: nil,
            linkReady: false
        )
    }

    /// Tier 1: called after presign returns the optimistic short URL and the
    /// client copies it to clipboard. Upload is still in flight; banner swaps
    /// the headline to acknowledge the copy.
    public func markLinkReady(clientJobId: UUID, shortUrl: String) {
        guard var c = current, c.clientJobId == clientJobId else { return }
        c.shortUrl = shortUrl
        c.linkReady = true
        c.stage = .uploading
        current = c
    }

    public func updateProgress(clientJobId: UUID,
                               progress: Double,
                               bytesSent: Int64,
                               bytesTotal: Int64,
                               stage: ActiveUpload.Stage = .uploading) {
        guard var c = current, c.clientJobId == clientJobId else { return }
        c.progress = max(0, min(1, progress))
        c.bytesSent = bytesSent
        c.bytesTotal = bytesTotal
        c.stage = stage
        current = c
    }

    public func updateStage(clientJobId: UUID,
                            stage: ActiveUpload.Stage,
                            progress: Double? = nil,
                            bytesSent: Int64? = nil,
                            bytesTotal: Int64? = nil) {
        guard var c = current, c.clientJobId == clientJobId else { return }
        c.stage = stage
        if let progress {
            c.progress = max(0, min(1, progress))
        }
        if let bytesSent {
            c.bytesSent = bytesSent
        }
        if let bytesTotal {
            c.bytesTotal = bytesTotal
        }
        current = c
    }

    public func finishSuccess(clientJobId: UUID, shortUrl: String) {
        guard var c = current, c.clientJobId == clientJobId else { return }
        c.phase = .completed
        c.progress = 1.0
        c.shortUrl = shortUrl
        current = c
        scheduleAutoDismiss(after: 2.5)
    }

    public func finishFailure(clientJobId: UUID, reason: String) {
        guard var c = current, c.clientJobId == clientJobId else { return }
        c.phase = .failed
        c.error = reason
        current = c
        scheduleAutoDismiss(after: 4.0)
    }

    public func dismiss() {
        cancelPendingDismiss()
        current = nil
    }

    private func scheduleAutoDismiss(after seconds: TimeInterval) {
        cancelPendingDismiss()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    private func cancelPendingDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }
}
