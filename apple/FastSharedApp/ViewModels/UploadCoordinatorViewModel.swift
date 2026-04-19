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
            let jobs = try await uploadService.enqueueDrop(urls: urls)
            activeJobs.append(contentsOf: jobs)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
