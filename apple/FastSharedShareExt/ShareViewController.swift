import Foundation
import SwiftUI
import UniformTypeIdentifiers
import FastSharedCore
import OSLog

#if canImport(UIKit)
import UIKit
typealias PlatformViewController = UIViewController
#elseif canImport(AppKit)
import AppKit
typealias PlatformViewController = NSViewController
#endif

@MainActor
final class ShareViewController: PlatformViewController {
    private let log = Logger(subsystem: Log.subsystem, category: "share")
    private let viewModel = ShareViewModel()
    private let paywallCoordinator = PaywallCoordinator()
    private var autoDismissTask: Task<Void, Never>?
    private var subscriptionStore: SubscriptionStore?

    #if canImport(UIKit)
    override func viewDidLoad() {
        super.viewDidLoad()
        embed(makeRootView())
        Task { await ingestAttachments() }
        observeDismissal()
    }

    private func embed(_ root: some View) {
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
    #elseif canImport(AppKit)
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 440))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        embed(makeRootView())
        Task { await ingestAttachments() }
        observeDismissal()
    }

    private func embed(_ root: some View) {
        let host = NSHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    #endif

    private func makeRootView() -> ShareRootView {
        bootstrapSubscriptionStore()
        return ShareRootView(viewModel: viewModel,
                             paywallCoordinator: paywallCoordinator,
                             onUpload: { [weak self] in
                                 await self?.performUpload()
                             },
                             onCancel: { [weak self] in
                                 self?.cancel()
                             },
                             onDismiss: { [weak self] in
                                 self?.completeAndDismiss()
                             })
    }

    /// Stand up a share-ext-local SubscriptionStore so the tier cap lookup in
    /// UploadService.preflight has data without having to re-enter StoreKit.
    /// Reads cached snapshot from App Group — main app seeds it on every
    /// successful verify.
    private func bootstrapSubscriptionStore() {
        guard subscriptionStore == nil else { return }
        let keychain = KeychainStore(service: AppGroupConfig.identifier, accessGroup: AppGroupConfig.keychainAccessGroup)
        let tokenStore = DeviceTokenStore(keychain: keychain)
        let apiClient = APIClient(tokenStore: tokenStore)
        let store = SubscriptionStore(apiClient: apiClient)
        subscriptionStore = store
        Task {
            await SubscriptionStoreLocator.shared.install(store)
            await store.start()
            // WHY: share ext is short-lived — don't block on a network refresh.
            // The cached snapshot (isPro/caps) is enough for preflight decisions.
            await store.replayEntitlementsVerification()
        }
    }

    /// Observes the ViewModel for explicit dismissal / cancel signals coming from SwiftUI.
    private func observeDismissal() {
        // WHY: we rely on a small Task that polls the two dismissal flags rather than wiring Combine; the
        // extension lives briefly and we want zero new observation machinery in the view layer.
        Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                if self.viewModel.cancelled {
                    self.cancel()
                    return
                }
                if self.viewModel.readyToDismiss {
                    self.completeAndDismiss()
                    return
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    private func ingestAttachments() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        var staged: [StagedItem] = []
        for item in items {
            guard let providers = item.attachments else { continue }
            for provider in providers {
                if let entry = await stage(provider: provider) {
                    staged.append(entry)
                }
            }
        }
        await MainActor.run {
            viewModel.items = staged
        }
    }

    private func stage(provider: NSItemProvider) async -> StagedItem? {
        // WHY: binary UTIs come first. When loaded via loadFileRepresentation,
        // `public.file-url` returns a sidecar file (a .webloc-style text blob
        // containing the URL), not the real payload. Apps like CleanShot,
        // Xnapper, and Finder register both .image AND .fileURL on the same
        // provider — if we pick .fileURL first we upload a 100-byte text file
        // instead of the PNG the user actually meant to share.
        let binaryCandidates: [UTType] = [.image, .movie, .pdf, .audio, .data, .item]
        for type in binaryCandidates where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let staged = await loadFileRepresentation(provider: provider, typeIdentifier: type.identifier) {
                return staged
            }
        }
        // Fallback: only a public.file-url representation was offered (e.g. some
        // macOS Finder shares). Resolve the URL via loadItem and copy the real
        // file from disk.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let staged = await resolveFileURL(provider: provider) {
                return staged
            }
        }
        return nil
    }

    private func resolveFileURL(provider: NSItemProvider) async -> StagedItem? {
        await withCheckedContinuation { continuation in
            _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    self.log.error("fileURL loadItem failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }
                let resolved: URL?
                if let direct = item as? URL { resolved = direct }
                else if let data = item as? Data { resolved = URL(dataRepresentation: data, relativeTo: nil) }
                else { resolved = nil }
                guard let url = resolved else {
                    self.log.error("fileURL loadItem returned a non-URL item")
                    continuation.resume(returning: nil)
                    return
                }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let destination = try AppGroupPaths.stagingDirectory().appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
                    try self.streamCopy(from: url, to: destination)
                    let filename = url.lastPathComponent
                    let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
                    let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    let staged = StagedItem(localURL: destination,
                                            contentType: contentType,
                                            sizeBytes: size,
                                            filename: filename)
                    continuation.resume(returning: staged)
                } catch {
                    self.log.error("fileURL stage copy failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadFileRepresentation(provider: NSItemProvider, typeIdentifier: String) async -> StagedItem? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    self.log.error("loadFileRepresentation failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                do {
                    let destination = try AppGroupPaths.stagingDirectory().appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
                    try self.streamCopy(from: url, to: destination)
                    let filename = url.lastPathComponent
                    let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
                    let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    let item = StagedItem(localURL: destination,
                                          contentType: contentType,
                                          sizeBytes: size,
                                          filename: filename)
                    continuation.resume(returning: item)
                } catch {
                    self.log.error("stage copy failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func streamCopy(from source: URL, to destination: URL) throws {
        // WHY: streaming avoids ever holding the full payload in memory inside the extension sandbox.
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }
        while true {
            let chunk = try input.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            try output.write(contentsOf: chunk)
        }
    }

    private func performUpload() async {
        // WHY: the share ext stays open showing live progress. We can't rely
        // on the URL-scheme handoff because iOS blocks `extensionContext.open`
        // when the main app is force-quit (documented Apple policy), so the
        // user would get zero feedback if we dismissed immediately. Instead:
        //   1. `enqueue` stages the URLSession background task (so it keeps
        //      running even if the user leaves before we finish).
        //   2. We poll the SwiftData job row via `startObserving` and render
        //      progress inside the sheet.
        //   3. When the upload completes, the orchestrator copies the link
        //      to the clipboard; the sheet briefly shows a success card,
        //      then the view model flips `readyToDismiss` and we close.
        //
        // Live Activity: still parked via `startOrDefer` inside `enqueue`.
        // When the main app next opens, `drainPendingStarts` creates the
        // Activity in the process that owns the widget descriptors — at
        // which point the Dynamic Island animates for whatever state the
        // upload is in (usually already completed by then).
        guard let first = await viewModel.items.first else {
            log.error("performUpload invoked with zero staged items")
            return
        }

        await MainActor.run {
            viewModel.phase = .preparing
        }

        let keychain = KeychainStore(service: AppGroupConfig.identifier, accessGroup: AppGroupConfig.keychainAccessGroup)
        let tokenStore = DeviceTokenStore(keychain: keychain)
        let apiClient = APIClient(tokenStore: tokenStore)
        let store = SwiftDataStore.shared
        let orchestrator = UploadOrchestrator(apiClient: apiClient, store: store, clipboard: Clipboard.make())
        BackgroundSessionManager.shared.bind(orchestrator: orchestrator, store: store)
        let service = UploadService(
            apiClient: apiClient,
            store: store,
            tokenStore: tokenStore,
            background: BackgroundSessionManager.shared,
            orchestrator: orchestrator,
            subscriptionStore: subscriptionStore
        )

        let policy = await viewModel.retentionPolicy
        do {
            let job = try await service.enqueue(
                stagedURL: first.localURL,
                contentType: first.contentType,
                originalFilename: first.filename,
                retentionPolicy: policy
            )
            log.info("share ext enqueued file=\(first.filename, privacy: .public) retentionPolicy=\(policy.rawValue, privacy: .public)")

            await MainActor.run {
                viewModel.startObserving(
                    clientJobId: job.clientJobId,
                    filename: first.filename,
                    totalBytes: first.sizeBytes
                )
            }

            // Fire-and-forget additional items — UI tracks only the first.
            let remaining = await viewModel.items.dropFirst()
            for item in remaining {
                Task.detached {
                    _ = try? await service.enqueue(
                        stagedURL: item.localURL,
                        contentType: item.contentType,
                        originalFilename: item.filename,
                        retentionPolicy: policy
                    )
                }
            }
        } catch let gate as SubscriptionGate {
            await MainActor.run {
                viewModel.phase = .idle
                switch gate {
                case .dailyCapReached(let used, let cap):
                    paywallCoordinator.present(.dailyCapReached(used: used, cap: cap))
                case .fileTooLarge(let size, _):
                    paywallCoordinator.present(.largeFileRequested(sizeBytes: size))
                case .retentionTooLong:
                    paywallCoordinator.present(.longRetentionRequested(policy: policy))
                case .cloudSyncRequiresPro:
                    paywallCoordinator.present(.cloudSyncRequested)
                }
            }
        } catch let api as APIError {
            if case .paymentRequired(let code, _) = api {
                await MainActor.run {
                    viewModel.phase = .idle
                    paywallCoordinator.present(.serverForced(errorCode: code))
                }
                return
            }
            log.error("share ext enqueue api error: \(api.localizedDescription, privacy: .public)")
            await MainActor.run {
                viewModel.reportEnqueueFailure(error: api, requestId: UUID())
            }
        } catch {
            log.error("share ext enqueue failed: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                viewModel.reportEnqueueFailure(error: error, requestId: UUID())
            }
        }
    }

    private func completeAndDismiss() {
        autoDismissTask?.cancel()
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func cancel() {
        autoDismissTask?.cancel()
        extensionContext?.cancelRequest(withError: NSError(domain: "dev.kindrazki.fastshared.ShareExt",
                                                           code: NSUserCancelledError,
                                                           userInfo: nil))
    }
}
