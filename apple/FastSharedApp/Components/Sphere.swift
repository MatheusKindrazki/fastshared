import SwiftUI
import FastSharedCore

/// The warm origin sphere from `design/screens.jsx` `Sphere()`.
///
/// A radial-gradient ball with a soft glow halo + subtle highlight. This is
/// the hero motif used in the onboarding backdrop and the share-success screen.
struct Sphere: View {
    var size: CGFloat = 80
    var glow: Bool = true

    var body: some View {
        let accent = BrandPalette.amberAccent

        ZStack {
            if glow {
                // Ambient amber halo behind the ball.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent.hot.opacity(0.25), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.8
                        )
                    )
                    .frame(width: size * 1.6, height: size * 1.6)
                    .blur(radius: 4)
            }

            // The core sphere — warm gradient shifted to the upper left,
            // fading to a deep burnt terracotta on the lower right.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.965, blue: 0.878),
                            accent.soft,
                            accent.hot,
                            Color(red: 0.655, green: 0.231, blue: 0.078)
                        ],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: 0,
                        endRadius: size * 0.85
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: accent.hot.opacity(0.54), radius: size * 0.3)
                .overlay(
                    // Inner shadow on the bottom-right edge.
                    Circle()
                        .strokeBorder(Color.black.opacity(0.2), lineWidth: 2)
                        .blur(radius: 3)
                        .mask(Circle())
                )

            // Specular highlight — the sphere's glint.
            Ellipse()
                .fill(Color.white.opacity(0.6))
                .frame(width: size * 0.30, height: size * 0.18)
                .blur(radius: 1)
                .offset(x: -size * 0.13, y: -size * 0.22)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 32) {
        Sphere(size: 40)
        Sphere(size: 80)
        Sphere(size: 140)
    }
    .padding(40)
    .background(BrandPalette.ground)
}
