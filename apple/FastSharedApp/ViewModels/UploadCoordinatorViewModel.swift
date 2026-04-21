import Foundation
import Observation
import FastSharedCore

@Observable
@MainActor
final class UploadCoordinatorViewModel {
    var activeJobs: [UploadJob] = []
    var lastError: String?

    private let uploadService: UploadServiceProtocol

    init(uploadService: UploadServiceProtocol) {
        self.uploadService = uploadService
    }

    func enqueueFromDrop(urls: [URL]) async {
        lastError = nil
        do {
            // M3: drop result is polymorphic — bundle path returns a single
            // headline; UI for the bundle aggregate progress lands in M4.
            switch try await uploadService.enqueueDrop(urls: urls) {
            case .single(let job):
                activeJobs.append(job)
            case .bundle(let bundle):
                // TODO(M4): wire bundle.aggregateProgress to a Live Activity
                // and show the bundle short URL in a "Sent N files" banner.
                activeJobs.append(contentsOf: bundle.jobs)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
