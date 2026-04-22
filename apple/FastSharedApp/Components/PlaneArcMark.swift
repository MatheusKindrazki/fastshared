import SwiftUI
import FastSharedCore

/// PlaneArc — the v3 FastShared brand mark.
///
/// Ported 1:1 from `project/design/plane-arc.jsx` → `PA_Refined` (the variant
/// the team shipped). A single gradient arc (`fade@0 → hot@0.5 → soft@1`) in a
/// 140-unit viewBox with a dart-shaped plane tucked into its terminus (81, 66).
///
/// The mark always renders inside a `size × size` frame and maps the
/// 140-unit design coordinates onto that frame via `GeometryReader`-driven
/// scaling, so a 22pt chip and a 260pt hero draw from the same geometry.
///
/// Parameters honour the redesign brief:
///
///  - `size`:        outer square edge length in points.
///  - `accent`:      fallback stroke color (also used for the ambient halo);
///                   defaults to the semantic `BrandPalette.accent.hot`
///                   (violet under the redesign).
///  - `gradient`:    the arc stroke gradient; defaults to `.brandArc`
///                   (fade→hot→soft) which reads the current `accent`.
///  - `planeColor`:  dart fill; defaults to `BrandPalette.text` (milk).
///  - `framed`:      when true, paints the 140x140 surface tile (surface0 fill,
///                   `lineStrong` stroke, 32pt rounded corner) behind the mark.
///                   When false, mark only — transparent background.
///  - `ambient`:     optional radial halo for hero moments.
///  - `animated`:    when true, plays the brand-intro motion on first appear.
///                   Honours `@Environment(\.accessibilityReduceMotion)`.
///
/// Swift-strict-concurrency note: this view is a pure value-type `View`; all
/// state is `@State` on the main actor. Animations run via `withAnimation`
/// on-appear — no custom timers / actors required.
struct PlaneArcMark: View {
    /// Outer square edge length in points.
    var size: CGFloat = 140
    /// Fallback accent color for the ambient halo + default gradient fallback.
    var accent: Color = BrandPalette.accent.hot
    /// Arc stroke gradient. Defaults to `.brandArc` (fade→hot→soft on the
    /// current `BrandPalette.accent`). Pass a custom gradient to re-tint.
    var gradient: Gradient = .brandArc
    /// Dart fill color. Defaults to `BrandPalette.text` (milk on ink).
    var planeColor: Color = BrandPalette.text
    /// When true, paints the 140x140 surface tile (rx 32) behind the mark.
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
        // viewBox-140 → local scale
        let corner = size * (32.0 / 140.0)
        let arcStrokeWidth = size * (9.0 / 140.0)

        ZStack {
            // Ambient halo — radial-gradient accent fade, inset -35% around the mark.
            // Matches plane-arc.jsx `radial-gradient(circle, ${t.hot}35 0%, transparent 65%)`
            // with a 6pt blur.
            if ambient {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent.opacity(0.21), .clear],
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

            // Arc — endpoint tucks under the plane tail. The butt cap prevents a 1px violet halo behind the dart.
            // Gradient: fade@0 → hot@0.5 → soft@1 along bottom-left → top-right.
            ArcPath()
                .trim(from: 0, to: animated && !reduceMotion ? arcProgress : 1)
                .stroke(
                    LinearGradient(
                        gradient: gradient,
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    style: StrokeStyle(lineWidth: arcStrokeWidth, lineCap: .butt)
                )
                .frame(width: size, height: size)

            // Plane dart — tucked into the terminus (81, 66) scaled ×1.1 in viewBox-140 units.
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

    /// Dart plane — matches the `planeDart` path in plane-arc.jsx scaled by 1.1
    /// and translated to (81, 66) in the 140-unit viewBox. Includes the thin
    /// 35%-opacity secondary stroke along the belly seam (M 4 4 L 14 10).
    private var planeDart: some View {
        GeometryReader { geo in
            let s = geo.size.width / 140.0
            let transform = CGAffineTransform(translationX: 81 * s, y: 66 * s)
                .scaledBy(x: 1.1 * s, y: 1.1 * s)

            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0).applying(transform))
                    p.addLine(to: CGPoint(x: 22, y: -26).applying(transform))
                    p.addLine(to: CGPoint(x: 14, y: 10).applying(transform))
                    p.addLine(to: CGPoint(x: 4, y: 4).applying(transform))
                    p.addLine(to: CGPoint(x: 0, y: 18).applying(transform))
                    p.addLine(to: CGPoint(x: -8, y: 4).applying(transform))
                    p.closeSubpath()
                }
                .fill(planeColor)

                Path { p in
                    p.move(to: CGPoint(x: 4, y: 4).applying(transform))
                    p.addLine(to: CGPoint(x: 14, y: 10).applying(transform))
                }
                .stroke(planeColor.opacity(0.35), lineWidth: 1)
            }
        }
    }
}

/// The arc path from `PA_Refined`, trimmed to tuck under the plane tail in a 140-unit viewBox.
struct ArcPath: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 140.0
        var p = Path()
        p.move(to: CGPoint(x: 26 * s, y: 110 * s))
        p.addQuadCurve(
            to: CGPoint(x: 80 * s, y: 72 * s),
            control: CGPoint(x: 60 * s, y: 98 * s)
        )
        return p
    }
}

// MARK: - Gradient presets

extension Gradient {
    /// Signature brand arc gradient: `fade@0 → hot@0.5 → soft@1`, reading the
    /// semantic `BrandPalette.accent` (violet in the redesign).
    ///
    /// This is the gradient the mark uses by default. Pass a custom `Gradient`
    /// to re-tint without changing the accent globally.
    static var brandArc: Gradient {
        let a = BrandPalette.accent
        return Gradient(stops: [
            .init(color: a.fade.opacity(0), location: 0),
            .init(color: a.hot.opacity(0.95), location: 0.5),
            .init(color: a.soft, location: 1),
        ])
    }

    /// Amber variant for consumers that want the original warm brand look.
    static var brandArcAmber: Gradient {
        let a = BrandPalette.amberAccent
        return Gradient(stops: [
            .init(color: a.fade.opacity(0), location: 0),
            .init(color: a.hot.opacity(0.95), location: 0.5),
            .init(color: a.soft, location: 1),
        ])
    }
}

// MARK: - Lockup

/// Horizontal lockup — mark + wordmark, per `plane-arc.jsx` → `LockupHoriz`.
///
/// Renders `PlaneArcMark` at `size` and the wordmark `fastshared.` at a
/// scaled type size + tracking so the pair reads as a single glyph at any
/// presentation scale. The period is painted in the current accent hot.
struct PlaneArcLockupHorizontal: View {
    /// Edge length of the leading mark. The wordmark scales proportionally
    /// (`size × 0.62`) and the gap is `size × 0.27` (≈14pt at the 52pt base).
    var size: CGFloat = 52
    /// Custom accent override — defaults to the semantic `BrandPalette.accent`.
    var accent: BrandPalette.Accent = BrandPalette.accent

    var body: some View {
        let gap = size * 0.27
        let wordSize = size * 0.62
        HStack(spacing: gap) {
            PlaneArcMark(
                size: size,
                accent: accent.hot,
                gradient: .brandArc
            )
            .accessibilityHidden(true)

            LockupWordmark(size: wordSize, accent: accent.hot)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("fastshared")
    }
}

/// The `fastshared.` wordmark — system rounded-bold (on-device stand-in for
/// Bricolage Grotesque) with tracking scaled to `-0.035 * size` so visual
/// density stays constant across sizes. The trailing period is painted in
/// the current accent hot.
struct LockupWordmark: View {
    var size: CGFloat = 32
    var accent: Color = BrandPalette.accent.hot
    var baseColor: Color = BrandPalette.text

    var body: some View {
        (
            Text("fastshared")
                .foregroundStyle(baseColor)
            + Text(".")
                .foregroundStyle(accent)
        )
        .font(.system(size: size, weight: .bold, design: .rounded))
        .tracking(-size * 0.035)
    }
}

#Preview("Sizes — dark") {
    VStack(spacing: 32) {
        PlaneArcMark(size: 64)
        PlaneArcMark(size: 96, framed: true)
        PlaneArcMark(size: 140, framed: true, ambient: true)
        PlaneArcLockupHorizontal(size: 52)
    }
    .padding(40)
    .background(BrandPalette.ground)
    .preferredColorScheme(.dark)
}

#Preview("Sizes — light") {
    VStack(spacing: 32) {
        PlaneArcMark(
            size: 64,
            planeColor: Color(red: 0.03, green: 0.01, blue: 0.09)
        )
        PlaneArcMark(
            size: 96,
            planeColor: Color(red: 0.03, green: 0.01, blue: 0.09),
            framed: true,
            background: Color.white
        )
        PlaneArcLockupHorizontal(size: 52)
    }
    .padding(40)
    .background(Color(red: 0.96, green: 0.95, blue: 0.92))
    .preferredColorScheme(.light)
}
