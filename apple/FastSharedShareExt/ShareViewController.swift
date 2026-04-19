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

    #if canImport(UIKit)
    override func viewDidLoad() {
        super.viewDidLoad()
        embed(makeRootView())
        Task { await ingestAttachments() }
    }

    private func embed(_ root: some View) {
        let host = UIHostingController(rootView: root)
        addChild(host)
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
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 300))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        embed(makeRootView())
        Task { await ingestAttachments() }
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
        ShareRootView(viewModel: viewModel, onUpload: { [weak self] in
            await self?.performUpload()
        }, onCancel: { [weak self] in
            self?.cancel()
        })
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
        await viewModel.beginUploading()
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

        let policy = viewModel.retentionPolicy
        for item in viewModel.items {
            do {
                _ = try await service.enqueue(stagedURL: item.localURL,
                                              contentType: item.contentType,
                                              originalFilename: item.filename,
                                              retentionPolicy: policy)
                log.info("share uploaded file=\(item.filename, privacy: .public) retentionPolicy=\(policy.rawValue, privacy: .public)")
            } catch {
                log.error("enqueue failed retentionPolicy=\(policy.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        await finishRequest()
    }

    private func finishRequest() async {
        await MainActor.run {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "com.yourco.fastshared.ShareExt",
                                                           code: NSUserCancelledError,
                                                           userInfo: nil))
    }
}
