import SwiftUI
import FastSharedCore

/// BrandLockup — horizontal mark + wordmark, per `design/screens.jsx` → `BrandLockup`.
///
/// The canonical in-app brand signature: a bare `PlaneArcMark` followed by the
/// wordmark `fastshared` with a single amber period as the only ornament.
///
///     BrandLockup(markSize: 26, textSize: 15)    // Hub header
///     BrandLockup(markSize: 20, textSize: 13)    // Share-ext sheet header
///
/// The mark stays unframed (`framed: false`) so the lockup reads as a single
/// wordmark glyph — frames are reserved for hero moments (onboarding, success).
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
        let accent = BrandPalette.amberAccent
        HStack(spacing: 8) {
            // Override PlaneArcMark's default violet (accent.hot) with amber —
            // the brand accent actually used across Settings/Paywall/SignIn/
            // Splash. Keeps the lockup visually consistent with every other
            // amber CTA and avoids the solitary-violet-logo look reported.
            PlaneArcMark(
                size: markSize,
                accent: accent.hot,
                gradient: Gradient(colors: [.clear, accent.hot, accent.soft])
            )
            .accessibilityHidden(true)

            (
                Text("fastshared")
                    .foregroundStyle(wordmarkColor)
                + Text(".")
                    .foregroundStyle(accent.hot)
            )
            .font(.system(size: textSize, weight: .bold))
            // -0.02em tracking at this size rounds to a fraction of a point —
            // we approximate with a small negative tracking value.
            .tracking(-textSize * 0.02)
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
