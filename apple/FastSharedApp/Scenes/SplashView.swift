import SwiftUI
import FastSharedCore

/// Launch splash for the raster-backed v2 brand mark.
///
/// The old stroke-draw timeline does not match the new shaded/glow logo.
/// This reveal keeps motion simple: ambient light, mark scale/fade, then exit.
struct SplashView: View {
    var onComplete: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowOpacity: Double = 0
    @State private var markOpacity: Double = 0
    @State private var markScale: CGFloat = 0.94
    @State private var markBlur: CGFloat = 8
    @State private var rootOpacity: Double = 1

    private let size: CGFloat = 148

    var body: some View {
        ZStack {
            Color.sysBackground
                .ignoresSafeArea()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                FriendlyPalette.accentHot.opacity(colorScheme == .dark ? 0.24 : 0.34),
                                Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 1.25
                        )
                    )
                    .frame(width: size * 2.5, height: size * 2.5)
                    .blur(radius: 22)
                    .opacity(glowOpacity)
                    .allowsHitTesting(false)

                PlaneArcMark(size: size)
                    .opacity(markOpacity)
                    .scaleEffect(markScale)
                    .blur(radius: markBlur)
            }
            .opacity(rootOpacity)
        }
        .onAppear(perform: runTimeline)
        .accessibilityElement()
        .accessibilityLabel("FastShared")
    }

    private func runTimeline() {
        guard !reduceMotion else {
            glowOpacity = 1
            markOpacity = 1
            markScale = 1
            markBlur = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) {
                withAnimation(.easeInOut(duration: 0.20)) { rootOpacity = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.80) {
                onComplete()
            }
            return
        }

        withAnimation(.easeOut(duration: 0.45)) {
            glowOpacity = 1
        }

        withAnimation(.easeOut(duration: 0.72).delay(0.08)) {
            markOpacity = 1
            markScale = 1
            markBlur = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.60) {
            withAnimation(.easeInOut(duration: 0.20)) { rootOpacity = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.80) {
            onComplete()
        }
    }
}

#Preview("Splash - light") {
    SplashView()
        .preferredColorScheme(.light)
}

#Preview("Splash - dark") {
    SplashView()
        .preferredColorScheme(.dark)
}
