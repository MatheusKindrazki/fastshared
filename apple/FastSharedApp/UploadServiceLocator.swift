import Foundation
import FastSharedCore

// WHY: App Intents run in a minimal process context without the SwiftUI environment,
// so we expose the canonical service via an actor singleton. FastSharedApp installs
// its instance on launch; intents resolve it here.
public actor UploadServiceLocator {
    public static let shared = UploadServiceLocator()
    private var service: UploadServiceProtocol?

    public func install(_ service: UploadServiceProtocol) {
        self.service = service
    }

    public func current() throws -> UploadServiceProtocol {
        guard let service else { throw NotInstalled() }
        return service
    }

    public struct NotInstalled: Error, LocalizedError {
        public var errorDescription: String? {
            "FastShared isn't initialized yet — open the app once."
        }
    }
}
