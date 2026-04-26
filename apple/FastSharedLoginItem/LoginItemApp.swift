#if os(macOS)
import AppKit
import OSLog

@main
final class LoginItemAppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "dev.kindrazki.fastshared", category: "login-item")
    private let loginLaunchArgument = "--fastshared-launch-at-login"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.arguments = [loginLaunchArgument]

        NSWorkspace.shared.openApplication(at: containingApplicationURL(),
                                           configuration: configuration) { [log] _, error in
            if let error {
                log.error("Failed to launch FastShared at login: \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }

    private func containingApplicationURL() -> URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
#endif
