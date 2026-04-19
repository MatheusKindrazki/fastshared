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
