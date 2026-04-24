import XCTest

#if os(iOS)
import UIKit
#endif

final class AppStoreScreenshotsUITests: XCTestCase {
    private struct Scene {
        let rawValue: String
        let slug: String
    }

    private let scenes: [Scene] = [
        Scene(rawValue: "share-flow", slug: "share-flow"),
        Scene(rawValue: "retention", slug: "retention-picker"),
        Scene(rawValue: "progress", slug: "upload-progress"),
        Scene(rawValue: "history", slug: "history-revoke"),
        Scene(rawValue: "pro", slug: "pro-paywall"),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        for (index, scene) in scenes.enumerated() {
            let app = XCUIApplication()
            app.launchArguments = [
                "--fastshared-appstore-screenshots",
                "--fastshared-screenshot-scene=\(scene.rawValue)",
            ]
            app.launchEnvironment = [
                "FASTSHARED_SCREENSHOT_MODE": "1",
                "FASTSHARED_SCREENSHOT_SCENE": scene.rawValue,
            ]
            app.launch()
            addTeardownBlock { app.terminate() }

            let root = app.scrollViews["appstore-screenshot-root-\(scene.rawValue)"]
            XCTAssertTrue(root.waitForExistence(timeout: 15), "Screenshot scene did not appear: \(scene.rawValue)")

            waitForStableRender()

            let screenshot = captureScreenshot(from: app)
            let filename = String(format: "%02d_%@_%@.png", index + 1, deviceToken, scene.slug)
            let attachment = XCTAttachment(data: screenshot.pngRepresentation, uniformTypeIdentifier: "public.png")
            attachment.name = filename
            attachment.lifetime = .keepAlways
            add(attachment)

            app.terminate()
        }
    }

    private func waitForStableRender() {
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    }

    @MainActor
    private var deviceToken: String {
        #if os(macOS)
        return "APP_DESKTOP"
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "APP_IPAD_PRO_3GEN_129" : "APP_IPHONE_67"
        #else
        return "APP_UNKNOWN"
        #endif
    }

    @MainActor
    private func captureScreenshot(from app: XCUIApplication) -> XCUIScreenshot {
        #if os(macOS)
        let window = app.windows.firstMatch
        if window.waitForExistence(timeout: 5) {
            return window.screenshot()
        }
        return XCUIScreen.main.screenshot()
        #else
        return XCUIScreen.main.screenshot()
        #endif
    }
}
