import SwiftUI
import FastSharedCore

/// Raster-backed FastShared brand mark.
///
/// The v2 logo depends on soft glow and shaded paper-plane detail, so the
/// canonical rendering is the shared asset catalog instead of hand-drawn
/// SwiftUI paths. The public initializer surface is intentionally kept close
/// to the old `PlaneArcMark` so existing call sites do not churn.
struct PlaneArcMark: View {
    var size: CGFloat = 140
    var accent: Color = BrandPalette.accent.hot
    var gradient: Gradient = .brandArc
    var planeColor: Color = BrandPalette.text
    var framed: Bool = false
    var background: Color? = nil
    var ambient: Bool = false
    var animated: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible: Bool = false

    private var assetName: String {
        framed ? "FastSharedIcon" : "FastSharedMark"
    }

    private var shouldAnimate: Bool {
        animated && !reduceMotion
    }

    var body: some View {
        ZStack {
            if ambient {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                accent.opacity(0.28),
                                Color.white.opacity(0.10),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.92
                        )
                    )
                    .frame(width: size * 1.72, height: size * 1.72)
                    .blur(radius: max(6, size * 0.08))
                    .opacity(shouldAnimate ? (visible ? 1 : 0) : 1)
                    .scaleEffect(shouldAnimate ? (visible ? 1 : 0.82) : 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if framed, let background {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(background)
                    .frame(width: size, height: size)
            }

            Image(assetName)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: framed ? size * 0.22 : 0, style: .continuous))
                .shadow(color: framed ? Color.black.opacity(0.16) : .clear, radius: framed ? size * 0.12 : 0, y: framed ? size * 0.05 : 0)
                .opacity(shouldAnimate ? (visible ? 1 : 0) : 1)
                .scaleEffect(shouldAnimate ? (visible ? 1 : 0.94) : 1)
                .blur(radius: shouldAnimate ? (visible ? 0 : 6) : 0)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard shouldAnimate else {
                visible = true
                return
            }
            withAnimation(.easeOut(duration: 0.72)) {
                visible = true
            }
        }
        .accessibilityLabel("fastshared mark")
    }
}

// MARK: - Compatibility gradient presets

extension Gradient {
    static var brandArc: Gradient {
        let a = BrandPalette.accent
        return Gradient(stops: [
            .init(color: a.fade.opacity(0), location: 0),
            .init(color: a.hot.opacity(0.95), location: 0.5),
            .init(color: a.soft, location: 1),
        ])
    }

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

struct PlaneArcLockupHorizontal: View {
    var size: CGFloat = 52
    var accent: BrandPalette.Accent = BrandPalette.accent

    var body: some View {
        let gap = size * 0.27
        let wordSize = size * 0.62
        HStack(spacing: gap) {
            PlaneArcMark(size: size, accent: accent.hot, framed: true)
                .accessibilityHidden(true)

            LockupWordmark(size: wordSize, accent: accent.hot)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("fastshared")
    }
}

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
        .tracking(0)
    }
}

#Preview("Sizes") {
    VStack(spacing: 32) {
        PlaneArcMark(size: 64)
        PlaneArcMark(size: 96, framed: true)
        PlaneArcMark(size: 140, framed: true, ambient: true, animated: true)
        PlaneArcLockupHorizontal(size: 52)
    }
    .padding(40)
    .background(BrandPalette.ground)
    .preferredColorScheme(.dark)
}
