import Foundation

enum AppStoreScreenshotScene: String, CaseIterable {
    case shareFlow = "share-flow"
    case retention = "retention"
    case progress = "progress"
    case history = "history"
    case pro = "pro"

    var fileSlug: String {
        switch self {
        case .shareFlow: return "share-flow"
        case .retention: return "retention-picker"
        case .progress: return "upload-progress"
        case .history: return "history-revoke"
        case .pro: return "pro-paywall"
        }
    }

    var headline: String {
        switch self {
        case .shareFlow:
            return "Share any file in one gesture."
        case .retention:
            return "Pick when the link disappears."
        case .progress:
            return "Watch uploads finish in the background."
        case .history:
            return "Keep control after you send."
        case .pro:
            return "Go Pro when you need more room."
        }
    }

    var subheadline: String {
        switch self {
        case .shareFlow:
            return "FastShared turns a file into a temporary short link and copies it automatically."
        case .retention:
            return "Default 24-hour links keep cleanup automatic. Pro unlocks up to 30 days."
        case .progress:
            return "Large files continue cleanly with visible progress and a ready-to-paste link."
        case .history:
            return "Find recent links, copy again, share, or revoke before expiration."
        case .pro:
            return "Unlimited daily uploads, 2 GB files, longer retention, and iCloud sync."
        }
    }
}

enum AppStoreScreenshotMode {
    static let launchArgument = "--fastshared-appstore-screenshots"
    private static let scenePrefix = "--fastshared-screenshot-scene="

    static var isEnabled: Bool {
        let process = ProcessInfo.processInfo
        return process.arguments.contains(launchArgument)
            || process.environment["FASTSHARED_SCREENSHOT_MODE"] == "1"
    }

    static var scene: AppStoreScreenshotScene {
        let process = ProcessInfo.processInfo
        if let raw = process.environment["FASTSHARED_SCREENSHOT_SCENE"],
           let scene = AppStoreScreenshotScene(rawValue: raw) {
            return scene
        }
        if let argument = process.arguments.first(where: { $0.hasPrefix(scenePrefix) }) {
            let raw = String(argument.dropFirst(scenePrefix.count))
            return AppStoreScreenshotScene(rawValue: raw) ?? .shareFlow
        }
        return .shareFlow
    }
}
