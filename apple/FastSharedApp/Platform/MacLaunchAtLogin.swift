#if os(macOS)
import AppKit
import FastSharedCore
import OSLog
import ServiceManagement
import SwiftUI

@MainActor
enum MacLaunchAtLoginController {
    static let loginItemBundleIdentifier = "dev.kindrazki.fastshared.LoginItem"
    static let loginLaunchArgument = "--fastshared-launch-at-login"

    /// One-shot flag (App Group defaults) marking that the launch-at-login
    /// default has already been applied. Versioned so a future policy change
    /// can re-run the default for everyone by bumping the suffix.
    private static let defaultAppliedKey = "launch_at_login_default_applied_v1"

    private static let log = Logger(subsystem: Log.subsystem, category: "launch-at-login")
    private static var initialWindowSuppressed = false

    static var wasLaunchedAtLogin: Bool {
        ProcessInfo.processInfo.arguments.contains(loginLaunchArgument)
    }

    static var status: SMAppService.Status {
        SMAppService.loginItem(identifier: loginItemBundleIdentifier).status
    }

    static var isEnabledOrNeedsApproval: Bool {
        switch status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    static var statusLabel: String {
        switch status {
        case .enabled:
            return "Menu bar only"
        case .requiresApproval:
            return "Needs approval"
        case .notRegistered:
            return "Off"
        case .notFound:
            return "Unavailable"
        @unknown default:
            return "Unknown"
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.loginItem(identifier: loginItemBundleIdentifier)
        if enabled {
            switch service.status {
            case .enabled:
                return
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
                return
            case .notRegistered, .notFound:
                break
            @unknown default:
                break
            }

            do {
                try service.register()
            } catch {
                if service.status != .enabled && service.status != .requiresApproval {
                    throw error
                }
            }
        } else {
            switch service.status {
            case .notRegistered, .notFound:
                return
            case .enabled, .requiresApproval:
                break
            @unknown default:
                break
            }

            do {
                try service.unregister()
            } catch {
                if service.status != .notRegistered {
                    throw error
                }
            }
        }
    }

    /// Enables launch-at-login by default on the very first run, then never
    /// touches it again — so a user who later turns it off in Settings stays
    /// off. Idempotent and safe to call on every boot.
    ///
    /// WHY first-launch-only: re-registering whenever we see `.notRegistered`
    /// would override the user's opt-out, which is the one thing a "default on"
    /// feature must not do. The App Group flag is the contract that the default
    /// has been honored exactly once.
    static func applyLaunchAtLoginDefaultOnFirstRunIfNeeded() {
        // Don't fight the system: when we're already being launched by the
        // login item, or rendering App Store screenshots, leave registration
        // untouched.
        guard !wasLaunchedAtLogin, !AppStoreScreenshotMode.isEnabled else { return }

        // WHY `?? .standard`: the one-shot flag is the ONLY thing that keeps a
        // later opt-out durable. If the App Group suite is unavailable (unsigned
        // dev builds — see repo napkin), `UserDefaults(suiteName:)` is nil and
        // the flag could never persist, so we'd re-register on every boot and
        // silently resurrect the user's "off". `.standard` is always non-nil and
        // per-app, which is the right scope for a per-Mac launch preference.
        let defaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier) ?? .standard
        guard defaults.bool(forKey: defaultAppliedKey) != true else { return }

        // Mark first regardless of outcome: this is a one-time courtesy, not a
        // retry loop. If registration can't complete now (e.g. transient
        // failure) we still respect that it was the user's first run and won't
        // nag on every subsequent boot.
        defaults.set(true, forKey: defaultAppliedKey)

        let service = SMAppService.loginItem(identifier: loginItemBundleIdentifier)
        switch service.status {
        case .enabled, .requiresApproval:
            // Already registered (or pending the user's approval) — nothing to do.
            log.info("Launch-at-login already active on first run; default no-op")
            return
        case .notRegistered, .notFound:
            break
        @unknown default:
            break
        }

        do {
            // Silent register. A resulting `.requiresApproval` is surfaced in
            // Settings via `statusLabel`; we deliberately do NOT open System
            // Settings here so the first boot is never interrupted.
            try service.register()
            log.info("Enabled launch-at-login by default on first run (status=\(String(describing: service.status), privacy: .public))")
        } catch {
            log.error("Default launch-at-login registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func prepareForApplicationLaunch(_ application: NSApplication) {
        guard wasLaunchedAtLogin, !AppStoreScreenshotMode.isEnabled else { return }
        application.setActivationPolicy(.accessory)
    }

    static func finishApplicationLaunch(_ application: NSApplication) {
        guard wasLaunchedAtLogin, !AppStoreScreenshotMode.isEnabled else { return }
        hideKnownMainWindows(in: application)
        for delay in [0.05, 0.25, 0.75] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                hideKnownMainWindows(in: application)
            }
        }
    }

    static func configureMainWindow(_ window: NSWindow?) {
        guard let window else { return }
        window.identifier = .fastSharedMainWindow
        suppressInitialMainWindowIfNeeded(window)
    }

    static func showMainWindow() {
        initialWindowSuppressed = true
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.identifier == .fastSharedMainWindow }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }

        log.warning("Main window was not available to restore")
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func hideKnownMainWindows(in application: NSApplication) {
        guard wasLaunchedAtLogin, !AppStoreScreenshotMode.isEnabled else { return }
        for window in application.windows where isMainWindowCandidate(window) {
            suppressInitialMainWindowIfNeeded(window)
        }
        application.hide(nil)
    }

    private static func suppressInitialMainWindowIfNeeded(_ window: NSWindow) {
        guard wasLaunchedAtLogin,
              !AppStoreScreenshotMode.isEnabled,
              !initialWindowSuppressed else { return }
        initialWindowSuppressed = true
        window.orderOut(nil)
        NSApp.hide(nil)
    }

    private static func isMainWindowCandidate(_ window: NSWindow) -> Bool {
        if window.identifier == .fastSharedSettingsWindow { return false }
        if window.identifier == .fastSharedMainWindow { return true }
        return window.canBecomeMain && window.styleMask.contains(.titled)
    }
}

extension NSUserInterfaceItemIdentifier {
    static let fastSharedMainWindow = NSUserInterfaceItemIdentifier("dev.kindrazki.fastshared.main-window")
    static let fastSharedSettingsWindow = NSUserInterfaceItemIdentifier("dev.kindrazki.fastshared.settings-window")
}

struct MacMainWindowBinder: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        Task { @MainActor in
            MacLaunchAtLoginController.configureMainWindow(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            MacLaunchAtLoginController.configureMainWindow(nsView.window)
        }
    }
}
#endif
