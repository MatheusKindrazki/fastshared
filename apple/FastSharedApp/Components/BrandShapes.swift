import SwiftUI
import FastSharedCore

/// Amber→coral arc that draws itself on appear (trim animation), ending in dust particles. Page-1 hero.
struct ArcMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arcEnd: CGFloat = 0
    @State private var pulse: Bool = false
    @State private var particlesOn: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let sphereCenter = CGPoint(x: w * 0.22, y: h * 0.72)
            let ghost = CGPoint(x: w * 0.80, y: h * 0.30)

            ZStack {
                // Origin sphere glow
                Circle()
                    .fill(BrandPalette.amber.opacity(0.25))
                    .frame(width: 220, height: 220)
                    .blur(radius: 46)
                    .scaleEffect(pulse || reduceMotion ? 1.0 : 0.85)
                    .opacity(pulse ? 1 : 0.55)
                    .position(sphereCenter)

                // Origin sphere
                Circle()
                    .fill(RadialGradient(colors: [BrandPalette.ember, BrandPalette.amber],
                                         center: .center,
                                         startRadius: 0,
                                         endRadius: 60))
                    .frame(width: 96, height: 96)
                    .shadow(color: BrandPalette.amber.opacity(0.6), radius: 28)
                    .position(sphereCenter)

                // The arc
                ArcShape(from: sphereCenter, to: ghost)
                    .trim(from: 0, to: reduceMotion ? 1 : arcEnd)
                    .stroke(BrandPalette.arc, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .blur(radius: 0.4)

                // Ghost node (the terminal point the arc dissolves into)
                Circle()
                    .stroke(BrandPalette.dust.opacity(0.8), lineWidth: 1.4)
                    .frame(width: 22, height: 22)
                    .position(ghost)
                    .opacity(arcEnd > 0.8 || reduceMotion ? 1 : 0)

                Circle()
                    .fill(BrandPalette.dust)
                    .frame(width: 6, height: 6)
                    .position(ghost)
                    .opacity(arcEnd > 0.8 || reduceMotion ? 1 : 0)

                // Fading particles after the ghost node
                ForEach(0..<5, id: \.self) { i in
                    let progress = CGFloat(i + 1) / 6
                    let x = ghost.x + progress * (w * 0.12)
                    let y = ghost.y - progress * 18
                    Circle()
                        .fill(BrandPalette.dust)
                        .frame(width: max(2, 9 - CGFloat(i) * 1.6), height: max(2, 9 - CGFloat(i) * 1.6))
                        .opacity(particlesOn || reduceMotion ? Double(5 - i) / 6.0 : 0)
                        .position(x: x, y: y)
                }
            }
        }
        .onAppear { animate() }
        .accessibilityHidden(true)
    }

    private func animate() {
        guard !reduceMotion else {
            arcEnd = 1
            pulse = true
            particlesOn = true
            return
        }
        withAnimation(.easeOut(duration: 1.4)) { arcEnd = 1 }
        withAnimation(BrandMotion.transition.delay(1.3)) { particlesOn = true }
        withAnimation(BrandMotion.pulse) { pulse = true }
    }
}

struct ArcShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let control = CGPoint(x: (from.x + to.x) / 2,
                              y: min(from.y, to.y) - rect.height * 0.18)
        path.move(to: from)
        path.addQuadCurve(to: to, control: control)
        return path
    }
}

/// A vertical thin line with a single amber bead sliding top→bottom on a 3s loop. Page-3 metaphor.
struct HourglassBead: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let x = geo.size.width / 2
            ZStack {
                Rectangle()
                    .fill(BrandPalette.milk.opacity(0.12))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .position(x: x, y: h / 2)

                Circle()
                    .fill(RadialGradient(colors: [BrandPalette.ember, BrandPalette.amber],
                                         center: .center,
                                         startRadius: 0,
                                         endRadius: 12))
                    .frame(width: 16, height: 16)
                    .shadow(color: BrandPalette.amber.opacity(0.8), radius: 14)
                    .position(x: x, y: progress * (h - 24) + 12)
            }
        }
        .onAppear { run() }
        .accessibilityHidden(true)
    }

    private func run() {
        guard !reduceMotion else {
            progress = 1
            return
        }
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: false)) {
            progress = 1
        }
    }
}

/// 2pt progress rail for the onboarding top edge. Fills amber→coral as the user advances.
struct ProgressLine: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(BrandPalette.milk.opacity(0.08))
                Rectangle()
                    .fill(BrandPalette.arc)
                    .frame(width: max(0, geo.size.width * CGFloat(fraction)))
            }
        }
        .frame(height: 2)
        .animation(BrandMotion.transition, value: fraction)
    }
}
