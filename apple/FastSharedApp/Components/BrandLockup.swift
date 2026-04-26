import SwiftUI
import FastSharedCore

/// BrandLockup - app icon tile + visual wordmark.
///
/// Textual metadata uses "FastShared"; this component renders the lowercase
/// brand glyph used in app chrome.
///
///     BrandLockup(markSize: 26, textSize: 15)    // Hub header
///     BrandLockup(markSize: 20, textSize: 13)    // Share-ext sheet header
///
struct BrandLockup: View {
    /// Edge length of the leading `PlaneArcMark` in points.
    var markSize: CGFloat = 22
    /// Font size of the `fastshared.` wordmark in points.
    var textSize: CGFloat = 15

    // WHY: `BrandPalette.text` is the dark-theme ink (near-white) — perfect on
    // `.ground` / `.groundDark`, but invisible on the Friendly light surface
    // (`#fbf8f1`). The wordmark needs to follow the scheme: dark ink on light,
    // bright ink on dark. We resolve against the ambient scheme at render.
    @Environment(\.colorScheme) private var colorScheme

    private var wordmarkColor: Color {
        colorScheme == .dark ? BrandPalette.friendlyTextDark : BrandPalette.friendlyText
    }

    var body: some View {
        HStack(spacing: 8) {
            PlaneArcMark(size: markSize, framed: true)
                .accessibilityHidden(true)

            (
                Text("fastshared")
                    .foregroundStyle(wordmarkColor)
                + Text(".")
                    .foregroundStyle(BrandPalette.accentHot)
            )
            .font(.system(size: textSize, weight: .bold))
            .tracking(0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("fastshared")
    }
}

#Preview {
    VStack(spacing: 24) {
        BrandLockup(markSize: 20, textSize: 13)
        BrandLockup(markSize: 26, textSize: 15)
        BrandLockup(markSize: 40, textSize: 24)
    }
    .padding(40)
    .background(BrandPalette.ground)
}
