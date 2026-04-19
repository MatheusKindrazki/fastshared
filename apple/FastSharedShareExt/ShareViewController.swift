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

final class ShareViewController: PlatformViewController {
    private let log = Logger(subsystem: Log.subsystem, category: "share")
    private let viewModel = ShareViewModel()
    private var autoDismissTask: Task<Void, Never>?

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
        ShareRootView(viewModel: viewModel,
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
        let candidates: [UTType] = [.fileURL, .image, .movie, .pdf, .data, .item]
        for type in candidates where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let staged = await loadFileRepresentation(provider: provider, typeIdentifier: type.identifier) {
                return staged
            }
        }
        return nil
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
        // Only one item is expected from a share sheet in the MVP shape. If multiple were staged we still only
        // track the first for UI state; the service will enqueue them all in the background.
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
        let service = UploadService(apiClient: apiClient,
                                    store: store,
                                    tokenStore: tokenStore,
                                    background: BackgroundSessionManager.shared,
                                    orchestrator: orchestrator)

        let policy = await viewModel.retentionPolicy
        do {
            let job = try await service.enqueue(stagedURL: first.localURL,
                                                contentType: first.contentType,
                                                originalFilename: first.filename,
                                                retentionPolicy: policy)
            log.info("share enqueued file=\(first.filename, privacy: .public) retentionPolicy=\(policy.rawValue, privacy: .public)")
            await MainActor.run {
                viewModel.startObserving(clientJobId: job.clientJobId,
                                         filename: first.filename,
                                         totalBytes: first.sizeBytes)
            }

            // Fire-and-forget any remaining items; their UI isn't tracked in MVP but they still upload.
            let remaining = await viewModel.items.dropFirst()
            for item in remaining {
                Task.detached {
                    _ = try? await service.enqueue(stagedURL: item.localURL,
                                                   contentType: item.contentType,
                                                   originalFilename: item.filename,
                                                   retentionPolicy: policy)
                }
            }
        } catch {
            log.error("enqueue failed retentionPolicy=\(policy.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
