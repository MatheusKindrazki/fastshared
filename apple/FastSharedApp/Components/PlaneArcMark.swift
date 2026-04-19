import SwiftUI
import FastSharedCore

/// PA_Refined — the "plane + arc" motion logo from `design/plane-arc.jsx`.
///
/// A rounded square frame holds a single gradient arc with a dart-shaped plane
/// perched at its terminus. When `animated == true`, the arc draws from 0 → 1
/// on appear and the plane slides along the last stretch + fades in.
struct PlaneArcMark: View {
    /// Outer square edge length in points.
    var size: CGFloat = 140
    /// When true, plays the brand-intro motion on first appear.
    var animated: Bool = false
    /// Optional background override. Default: `surface0`.
    var background: Color? = nil

    @State private var arcProgress: CGFloat = 0
    @State private var planeIn: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let accent = BrandPalette.amberAccent
        let bg = background ?? BrandPalette.surface0
        let corner = size * (32.0 / 140.0)
        let arcStrokeWidth = size * (9.0 / 140.0)

        ZStack {
            // Frame
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(bg)
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(BrandPalette.lineStrong, lineWidth: 1)
                )

            // Arc — drawn in viewBox 140 units, so scale from the reference coords.
            ArcPath()
                .trim(from: 0, to: animated && !reduceMotion ? arcProgress : 1)
                .stroke(
                    LinearGradient(
                        colors: [accent.fade.opacity(0), accent.hot.opacity(0.9), accent.soft],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    style: StrokeStyle(lineWidth: arcStrokeWidth, lineCap: .round)
                )
                .frame(width: size, height: size)

            // Plane dart — placed at the arc terminus (84, 64) in viewBox-140 units.
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

    /// Dart plane — matches the `planeDart` path in `plane-arc.jsx` scaled by 1.1
    /// and translated to (84, 64) in the 140-unit viewBox.
    private var planeDart: some View {
        GeometryReader { geo in
            let s = geo.size.width / 140.0
            Path { p in
                // Translate and scale — 1.1× scale, anchor (84, 64).
                let a = CGAffineTransform(translationX: 84 * s, y: 64 * s)
                    .scaledBy(x: 1.1 * s, y: 1.1 * s)
                p.move(to: CGPoint(x: 0, y: 0).applying(a))
                p.addLine(to: CGPoint(x: 22, y: -26).applying(a))
                p.addLine(to: CGPoint(x: 14, y: 10).applying(a))
                p.addLine(to: CGPoint(x: 4, y: 4).applying(a))
                p.addLine(to: CGPoint(x: 0, y: 18).applying(a))
                p.addLine(to: CGPoint(x: -4, y: 4).applying(a))
                p.closeSubpath()
            }
            .fill(BrandPalette.text)
        }
    }
}

/// The arc path from PA_Refined: `M 26 110 Q 60 98, 82 68` in a 140-unit viewBox.
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
        PlaneArcMark(size: 64)
        PlaneArcMark(size: 140, animated: true)
        PlaneArcMark(size: 200, background: .black)
    }
    .padding(40)
    .background(BrandPalette.ground)
}
