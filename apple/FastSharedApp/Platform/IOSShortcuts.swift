#if os(iOS)
import AppIntents
import Foundation
import FastSharedCore

struct UploadClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Upload clipboard"
    static var description = IntentDescription("Uploads the contents of the clipboard to FastShared and copies the short link back.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // WHY: this shortcut is intentionally a stub in the MVP - full clipboard-to-URL piping is
        // implemented once the desktop flow stabilizes. We surface a dialog so users know it is wired up.
        return .result(dialog: "Clipboard upload is not yet available in this build.")
    }
}

struct FastSharedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // WHY: the hero intent is screenshot sharing — it's the Action Button / Back Tap entry
        // point. Listed first so Siri surfaces it as the default suggestion for the app.
        AppShortcut(
            intent: FastShareScreenshotIntent(),
            phrases: [
                "Fast share in \(.applicationName)",
                "Fast share my screenshot with \(.applicationName)",
                "\(.applicationName) share screenshot"
            ],
            shortTitle: "Fast Share",
            systemImageName: "bolt.horizontal.fill"
        )
        AppShortcut(
            intent: UploadClipboardIntent(),
            phrases: [
                "Upload clipboard to \(.applicationName)",
                "Send clipboard with \(.applicationName)"
            ],
            shortTitle: "Upload clipboard",
            systemImageName: "doc.on.clipboard"
        )
    }
}
#endif
