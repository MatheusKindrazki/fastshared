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

@Observable
@MainActor
final class ShareViewModel {
    var items: [StagedItem] = []
    var isUploading: Bool = false
    var cancelled: Bool = false
    var retentionPolicy: RetentionPolicy

    init() {
        // WHY: honor the default picked in the main app's Settings; fall back to the global default if unset.
        let defaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
        let stored = defaults?.string(forKey: "default_retention_policy")
        self.retentionPolicy = stored.flatMap(RetentionPolicy.init(rawValue:)) ?? .default
    }

    func beginUploading() async {
        isUploading = true
    }

    func cancel() {
        cancelled = true
    }
}
