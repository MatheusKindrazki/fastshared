import XCTest
@testable import FastSharedCore

final class LastScreenshotFetcherTests: XCTestCase {
    func test_authorization_denied_has_actionable_description() {
        let error = LastScreenshotError.authorizationDenied
        let description = error.errorDescription ?? ""
        XCTAssertFalse(description.isEmpty)
        XCTAssertTrue(description.lowercased().contains("photos"))
    }

    func test_no_screenshot_found_has_description() {
        let error = LastScreenshotError.noScreenshotFound
        let description = error.errorDescription ?? ""
        XCTAssertFalse(description.isEmpty)
        XCTAssertTrue(description.lowercased().contains("screenshot"))
    }

    func test_export_preserves_underlying_reason() {
        let error = LastScreenshotError.export(underlying: "disk full")
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("disk full"))
    }

    func test_staged_screenshot_is_sendable_value_type() {
        let staged = StagedScreenshot(
            url: URL(fileURLWithPath: "/tmp/test.png"),
            sizeBytes: 42,
            capturedAt: Date(timeIntervalSince1970: 0),
            filename: "Screenshot 2026-01-01 00-00-00.png"
        )
        XCTAssertEqual(staged.sizeBytes, 42)
        XCTAssertEqual(staged.filename, "Screenshot 2026-01-01 00-00-00.png")
    }
}
