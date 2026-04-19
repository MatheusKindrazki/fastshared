#if os(iOS)
import AppIntents
import Foundation
import FastSharedCore

/// One-tap (or zero-tap, via Action Button / Siri / Back Tap) entry point that grabs the newest
/// screenshot, feeds it through the same upload pipeline the UI uses, and returns a dialog while
/// the orchestrator copies the resulting short link to the clipboard on `/complete`.
///
/// Runs headless (`openAppWhenRun = false`) so the user never leaves the app they just captured.
struct FastShareScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Fast Share last screenshot"
    static let description = IntentDescription(
        "Upload your most recent screenshot and copy the share link to the clipboard."
    )
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let staged = try await LastScreenshotFetcher.staged()
        let policy = RetentionPolicy.defaultFromAppGroup()
        let service = try await UploadServiceLocator.shared.current()
        _ = try await service.enqueue(
            stagedURL: staged.url,
            contentType: "image/png",
            originalFilename: staged.filename,
            retentionPolicy: policy
        )
        return .result(dialog: "Sharing — your link will land in the clipboard.")
    }
}
#endif
