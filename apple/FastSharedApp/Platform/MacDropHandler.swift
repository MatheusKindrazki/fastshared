#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import FastSharedCore

struct MacDropHandler: ViewModifier {
    let coordinator: UploadCoordinatorViewModel

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL, .image, .movie], isTargeted: nil) { providers in
                resolve(providers: providers)
                return true
            }
    }

    private func resolve(providers: [NSItemProvider]) {
        let coordinator = self.coordinator
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else { return }
            await coordinator.enqueueFromDrop(urls: urls)
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}

extension View {
    func fastSharedMacDrop(_ coordinator: UploadCoordinatorViewModel) -> some View {
        modifier(MacDropHandler(coordinator: coordinator))
    }
}
#endif
