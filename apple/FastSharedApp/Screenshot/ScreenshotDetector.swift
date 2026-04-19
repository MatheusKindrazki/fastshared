#if os(iOS)
import Foundation
import UIKit
import FastSharedCore
import OSLog

struct PendingScreenshot: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let capturedAt: Date?
    let sizeBytes: Int64
    let filename: String
}

/// Observes `userDidTakeScreenshotNotification` while FastShared is foregrounded and stages the
/// newest screenshot for a soft "upload?" affordance in the hub. The actual banner UI is
/// `ScreenshotBanner`.
@MainActor
@Observable
final class ScreenshotDetector {
    private(set) var pending: PendingScreenshot?
    private(set) var lastError: String?
    private(set) var successTick: Int = 0

    // WHY: observer storage is `nonisolated(unsafe)` so that `deinit` — which runs outside any
    // actor context — can remove the observer without a hop. The token is written once in `init`
    // and read once in `deinit`; there is no concurrent access.
    nonisolated(unsafe) private var observerToken: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?
    private var errorClearTask: Task<Void, Never>?
    private let log = Logger(subsystem: "dev.kindrazki.fastshared", category: "screenshot-detector")

    init() {
        observerToken = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // WHY: hop back onto the MainActor — NotificationCenter delivers on the queue we
            // asked for, but that's not strictly checkable by the concurrency model.
            Task { @MainActor [weak self] in
                self?.handleScreenshot()
            }
        }
    }

    deinit {
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func handleScreenshot() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.loadLatest()
        }
    }

    private func loadLatest() async {
        do {
            let staged = try await LastScreenshotFetcher.staged()
            guard !Task.isCancelled else { return }
            pending = PendingScreenshot(
                id: UUID(),
                url: staged.url,
                capturedAt: staged.capturedAt,
                sizeBytes: staged.sizeBytes,
                filename: staged.filename
            )
            lastError = nil
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = message
            log.error("Screenshot banner staging failed: \(message, privacy: .public)")
            // WHY: transient UX — the detector hides errors after a few seconds so the hub
            // doesn't accumulate stale state when the user has denied Photos access.
            errorClearTask?.cancel()
            errorClearTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.lastError = nil }
            }
        }
    }

    func accept() {
        guard let pending else { return }
        self.pending = nil
        Task { [weak self] in
            await self?.enqueue(pending: pending)
        }
    }

    private func enqueue(pending: PendingScreenshot) async {
        do {
            let service = try await UploadServiceLocator.shared.current()
            let policy = RetentionPolicy.defaultFromAppGroup()
            _ = try await service.enqueue(
                stagedURL: pending.url,
                contentType: "image/png",
                originalFilename: pending.filename,
                retentionPolicy: policy
            )
            await MainActor.run { [weak self] in
                self?.successTick &+= 1
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await MainActor.run { [weak self] in
                self?.lastError = message
            }
            log.error("Screenshot banner upload failed: \(message, privacy: .public)")
        }
    }

    func dismiss() {
        pending = nil
    }

    /// Called by the banner's auto-dismiss TimelineView once the 10s countdown fully drains.
    func autoDismissIfNeeded(for id: UUID) {
        if pending?.id == id {
            pending = nil
        }
    }
}
#endif
