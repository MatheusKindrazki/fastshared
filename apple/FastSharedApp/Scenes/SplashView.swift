import SwiftUI
import FastSharedCore

/// Launch splash — calm, elegant brand reveal. Variant A from the Splash
/// Preview design package (2026-04-19): mark only, no wordmark.
///
/// Timeline (1.8s total):
///   0.00 – 0.50s  ambient glow fades up   (easeOut)
///   0.10 – 1.00s  arc draws               (easeOut, trim 0 → 1)
///   0.55 – 1.30s  plane slides along arc  (spring, response 0.75)
///   0.55 – 0.80s  plane fades in          (easeIn)
///   1.60 – 1.80s  whole mark fades out    (easeInOut), then onComplete fires
///
/// Reduced-motion behavior: skips the timeline, holds the end frame for
/// ~0.6s, then fades out and reports complete. The mark is still seen but
/// without the staged reveal — vestibular-safe.
///
/// The caller owns what happens after the splash; we just animate alpha
/// and report `onComplete` at the 1.8s mark.
struct SplashView: View {
    var onComplete: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arcProgress: CGFloat = 0
    @State private var planeProgress: CGFloat = 0
    @State private var glowOpacity: Double = 0
    @State private var planeOpacity: Double = 0
    @State private var rootOpacity: Double = 1

    private let size: CGFloat = 140

    var body: some View {
        ZStack {
            // Splash background — matches design (light: paper white,
            // dark: friendly ground). Cross-fades to the app's cream ground
            // (light) or stays the same (dark) when the splash dismisses.
            (colorScheme == .dark ? FriendlyPalette.ground(.dark) : Color.white)
                .ignoresSafeArea()

            ZStack {
                // Ambient amber glow behind the mark — warmer on light, cooler
                // on dark to keep contrast with the night ground.
                Circle()
                    .fill(RadialGradient(
                        colors: [
                            FriendlyPalette.accentHot.opacity(colorScheme == .dark ? 0.18 : 0.32),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 1.2))
                    .frame(width: size * 2.4, height: size * 2.4)
                    .blur(radius: 20)
                    .opacity(glowOpacity)
                    .allowsHitTesting(false)

                AnimatedPlaneArc(
                    size: size,
                    arcProgress: arcProgress,
                    planeProgress: planeProgress,
                    planeOpacity: planeOpacity,
                    planeColor: colorScheme == .dark
                        ? FriendlyPalette.text(.dark)
                        : FriendlyPalette.text(.light)
                )
            }
            .opacity(rootOpacity)
        }
        .onAppear(perform: runTimeline)
        .accessibilityElement()
        .accessibilityLabel("FastShared")
    }

    // MARK: - Timeline

    private func runTimeline() {
        guard !reduceMotion else {
            arcProgress = 1
            planeProgress = 1
            glowOpacity = 1
            planeOpacity = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) {
                withAnimation(.easeInOut(duration: 0.20)) { rootOpacity = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.80) {
                onComplete()
            }
            return
        }

        withAnimation(.easeOut(duration: 0.5)) { glowOpacity = 1 }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.easeOut(duration: 0.9)) { arcProgress = 1 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeIn(duration: 0.25)) { planeOpacity = 1 }
            withAnimation(.spring(response: 0.75, dampingFraction: 0.78)) {
                planeProgress = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.60) {
            withAnimation(.easeInOut(duration: 0.20)) { rootOpacity = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.80) {
            onComplete()
        }
    }
}

// MARK: - Animated mark primitive

/// Standalone animated version of PlaneArcMark — takes progress values so the
/// splash can orchestrate the draw + slide sequence externally without
/// pulling in the full PlaneArcMark component (which has its own intro).
private struct AnimatedPlaneArc: View {
    let size: CGFloat
    let arcProgress: CGFloat   // 0…1 — stroke trim
    let planeProgress: CGFloat // 0…1 — position along the arc
    let planeOpacity: Double
    let planeColor: Color

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / 140
            let s: (CGFloat) -> CGFloat = { $0 * scale }
            let k: CGFloat = 1.1 * scale

            // Quadratic curve coordinates match PlaneArcMark.swift so the
            // splash mark and the static brand lockup share visual identity.
            let start = CGPoint(x: s(26), y: s(110))
            let control = CGPoint(x: s(60), y: s(98))
            let tip = CGPoint(x: s(84), y: s(64))

            ZStack {
                Path { p in
                    p.move(to: start)
                    p.addQuadCurve(to: tip, control: control)
                }
                .trim(from: 0, to: arcProgress)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: FriendlyPalette.accentFade.opacity(0), location: 0),
                            .init(color: FriendlyPalette.accentHot.opacity(0.95), location: 0.5),
                            .init(color: Color(red: 1.0, green: 0x5b / 255.0, blue: 0x1a / 255.0), location: 1.0),
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing),
                    style: StrokeStyle(lineWidth: s(9), lineCap: .round))

                let pos = quadPoint(start: start, control: control, end: tip, t: planeProgress)
                let tan = quadTangent(start: start, control: control, end: tip, t: planeProgress)
                let angle = atan2(tan.dy, tan.dx)

                PlaneDart(k: k, color: planeColor)
                    .rotationEffect(.radians(Double(angle - referenceAngle(start: start, end: tip))),
                                    anchor: .topLeading)
                    .offset(x: pos.x, y: pos.y)
                    .opacity(planeOpacity)
            }
        }
        .frame(width: size, height: size)
    }

    /// PlaneArcMark's dart is drawn with its own internal angle, so we
    /// normalize by the straight-line angle start→end; the rotation applied
    /// is the delta between the live tangent and that baseline.
    private func referenceAngle(start: CGPoint, end: CGPoint) -> CGFloat {
        atan2(end.y - start.y, end.x - start.x)
    }
}

private struct PlaneDart: View {
    let k: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x:  22 * k, y: -26 * k))
                p.addLine(to: CGPoint(x:  14 * k, y:  10 * k))
                p.addLine(to: CGPoint(x:   4 * k, y:   4 * k))
                p.addLine(to: CGPoint(x:   0,     y:  18 * k))
                p.addLine(to: CGPoint(x:  -4 * k, y:   4 * k))
                p.closeSubpath()
            }
            .fill(color)

            Path { p in
                p.move(to: CGPoint(x:  4 * k, y: 4 * k))
                p.addLine(to: CGPoint(x: 14 * k, y: 10 * k))
            }
            .stroke(color.opacity(0.35), lineWidth: 1)
        }
    }
}

// MARK: - Quadratic Bézier helpers

private func quadPoint(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
    let u = 1 - t
    let x = u*u*start.x + 2*u*t*control.x + t*t*end.x
    let y = u*u*start.y + 2*u*t*control.y + t*t*end.y
    return CGPoint(x: x, y: y)
}

private func quadTangent(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGVector {
    let u = 1 - t
    let dx = 2*u*(control.x - start.x) + 2*t*(end.x - control.x)
    let dy = 2*u*(control.y - start.y) + 2*t*(end.y - control.y)
    return CGVector(dx: dx, dy: dy)
}

#Preview("Splash — light") {
    SplashView()
        .preferredColorScheme(.light)
}

#Preview("Splash — dark") {
    SplashView()
        .preferredColorScheme(.dark)
}
