import SwiftUI
import FastSharedCore

/// Teal transfer rail that draws itself on appear. Page-1 hero.
struct ArcMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arcEnd: CGFloat = 0
    @State private var pulse: Bool = false
    @State private var particlesOn: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let source = CGPoint(x: w * 0.23, y: h * 0.70)
            let target = CGPoint(x: w * 0.80, y: h * 0.32)

            ZStack {
                // Source file slip.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.thinMaterial)
                    .frame(width: 118, height: 92)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(BrandPalette.line.opacity(0.9), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(BrandPalette.amber)
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(BrandPalette.lightText)
                                )
                            Capsule().fill(BrandPalette.line).frame(width: 74, height: 5)
                            Capsule().fill(BrandPalette.line.opacity(0.7)).frame(width: 52, height: 5)
                        }
                        .padding(14)
                    }
                    .rotationEffect(.degrees(pulse && !reduceMotion ? -2 : 0))
                    .position(source)

                // The arc
                ArcShape(from: source, to: target)
                    .trim(from: 0, to: reduceMotion ? 1 : arcEnd)
                    .stroke(BrandPalette.arc, style: StrokeStyle(lineWidth: 4, lineCap: .round))

                // Destination link chip.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BrandPalette.paper)
                    .frame(width: 156, height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(BrandPalette.amber.opacity(0.36), lineWidth: 1)
                    )
                    .overlay {
                        HStack(spacing: 7) {
                            Image(systemName: "link")
                                .font(.system(size: 12, weight: .bold))
                            Text("fastsha.red")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(BrandPalette.amber)
                    }
                    .shadow(color: BrandPalette.ink.opacity(0.08), radius: 16, y: 10)
                    .position(target)
                    .opacity(arcEnd > 0.8 || reduceMotion ? 1 : 0)

                // Fading transfer ticks after the destination.
                ForEach(0..<5, id: \.self) { i in
                    let progress = CGFloat(i + 1) / 6
                    let x = target.x + progress * (w * 0.12)
                    let y = target.y - progress * 18
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(BrandPalette.ember)
                        .frame(width: max(3, 12 - CGFloat(i) * 1.5), height: 3)
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

/// A vertical thin line with a single transfer bead sliding top→bottom on a 3s loop. Page-3 metaphor.
struct HourglassBead: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let x = geo.size.width / 2
            ZStack {
                Rectangle()
                    .fill(BrandPalette.line)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .position(x: x, y: h / 2)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BrandPalette.arc)
                    .frame(width: 16, height: 16)
                    .shadow(color: BrandPalette.amber.opacity(0.22), radius: 10)
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
                    .fill(BrandPalette.line.opacity(0.75))
                Rectangle()
                    .fill(BrandPalette.arc)
                    .frame(width: max(0, geo.size.width * CGFloat(fraction)))
            }
        }
        .frame(height: 2)
        .animation(BrandMotion.transition, value: fraction)
    }
}
