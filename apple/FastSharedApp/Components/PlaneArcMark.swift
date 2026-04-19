import SwiftUI
import FastSharedCore

/// PlaneArc — the v3 FastShared brand mark.
///
/// Ported 1:1 from `project/design/screens.jsx` → `PlaneArc({ size, framed, bg, ambient })`:
/// a single gradient arc (fade→hot→soft) in a 140-unit viewBox with a dart-shaped
/// plane perched at its terminus (84, 64). Two optional ornaments:
///
///  - `framed`: a 32pt rounded-square backdrop (surface0 by default, overridable
///              via `background`) with a hairline `lineStrong` border.
///  - `ambient`: a soft radial-gradient glow bleeding 35% past the mark edges —
///              the hero decoration used in onboarding / success screens.
///
/// `animated` is a SwiftUI bonus — when true, the arc draws from 0→1 and the
/// plane slides into place. Honours `accessibilityReduceMotion`.
///
/// Use the v3 API directly:
///
///     PlaneArcMark(size: 160, framed: true, ambient: true)
///
/// Swift-strict-concurrency note: this view is a pure value-type `View`; all
/// state is `@State` on the main actor. The `animated` animations run via
/// `withAnimation` on-appear — no custom timers / actors required.
struct PlaneArcMark: View {
    /// Outer square edge length in points.
    var size: CGFloat = 80
    /// When true, renders the 32pt rounded-square backdrop + hairline border.
    var framed: Bool = false
    /// Optional background override for the frame. Default: `surface0` (dark).
    var background: Color? = nil
    /// When true, paints an amber radial glow bleeding past the mark edges.
    var ambient: Bool = false
    /// When true, plays the brand-intro motion on first appear.
    var animated: Bool = false

    @State private var arcProgress: CGFloat = 0
    @State private var planeIn: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let accent = BrandPalette.amberAccent
        // viewBox-140 → local scale
        let corner = size * (32.0 / 140.0)
        let arcStrokeWidth = size * (9.0 / 140.0)

        ZStack {
            // Ambient halo — radial-gradient amber fade, inset -35% around the mark.
            // Matches screens.jsx `radial-gradient(circle, ${t.hot}35 0%, transparent 65%)`
            // with 6px blur.
            if ambient {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent.hot.opacity(0.21), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.82
                        )
                    )
                    .frame(width: size * 1.7, height: size * 1.7)
                    .blur(radius: 6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            // Frame
            if framed {
                let bg = background ?? BrandPalette.surface0
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .stroke(BrandPalette.lineStrong, lineWidth: 1)
                    )
                    .frame(width: size, height: size)
            }

            // Arc — viewBox-140: `M 26 110 Q 60 98, 82 68`.
            // Gradient: fade@0 → hot@0.5 → soft@1 along bottom-left → top-right.
            ArcPath()
                .trim(from: 0, to: animated && !reduceMotion ? arcProgress : 1)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: accent.fade.opacity(0), location: 0),
                            .init(color: accent.hot.opacity(0.95), location: 0.5),
                            .init(color: accent.soft, location: 1),
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    style: StrokeStyle(lineWidth: arcStrokeWidth, lineCap: .round)
                )
                .frame(width: size, height: size)

            // Plane dart — dart at terminus (84, 64) scaled ×1.1 in viewBox-140 units.
            planeDart
                .frame(width: size, height: size)
                .opacity(animated && !reduceMotion ? (planeIn ? 1 : 0) : 1)
                .offset(
                    x: animated && !reduceMotion ? (planeIn ? 0 : -size * 0.05) : 0,
                    y: animated && !reduceMotion ? (planeIn ? 0 : size * 0.05) : 0
                )
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animated, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.1)) {
                arcProgress = 1
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.85)) {
                planeIn = true
            }
        }
        .accessibilityLabel("fastshared mark")
    }

    /// Dart plane — matches the `planeDart` path in screens.jsx scaled by 1.1
    /// and translated to (84, 64) in the 140-unit viewBox. Includes the thin
    /// 35%-opacity secondary stroke along the belly seam (M 4 4 L 14 10).
    private var planeDart: some View {
        GeometryReader { geo in
            let s = geo.size.width / 140.0
            let transform = CGAffineTransform(translationX: 84 * s, y: 64 * s)
                .scaledBy(x: 1.1 * s, y: 1.1 * s)

            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0).applying(transform))
                    p.addLine(to: CGPoint(x: 22, y: -26).applying(transform))
                    p.addLine(to: CGPoint(x: 14, y: 10).applying(transform))
                    p.addLine(to: CGPoint(x: 4, y: 4).applying(transform))
                    p.addLine(to: CGPoint(x: 0, y: 18).applying(transform))
                    p.addLine(to: CGPoint(x: -4, y: 4).applying(transform))
                    p.closeSubpath()
                }
                .fill(BrandPalette.text)

                Path { p in
                    p.move(to: CGPoint(x: 4, y: 4).applying(transform))
                    p.addLine(to: CGPoint(x: 14, y: 10).applying(transform))
                }
                .stroke(BrandPalette.text.opacity(0.35), lineWidth: 1)
            }
        }
    }
}

/// The arc path from v3 `PlaneArc`: `M 26 110 Q 60 98, 82 68` in a 140-unit viewBox.
private struct ArcPath: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 140.0
        var p = Path()
        p.move(to: CGPoint(x: 26 * s, y: 110 * s))
        p.addQuadCurve(
            to: CGPoint(x: 82 * s, y: 68 * s),
            control: CGPoint(x: 60 * s, y: 98 * s)
        )
        return p
    }
}

#Preview {
    VStack(spacing: 32) {
        PlaneArcMark(size: 40)
        PlaneArcMark(size: 80, framed: true)
        PlaneArcMark(size: 160, framed: true, ambient: true)
        PlaneArcMark(size: 160, framed: true, ambient: true, animated: true)
    }
    .padding(40)
    .background(BrandPalette.ground)
}
