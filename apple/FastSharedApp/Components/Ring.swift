import SwiftUI
import FastSharedCore

/// Circular progress ring — SwiftUI port of `Ring()` in `design/screens.jsx`.
///
/// A track circle rendered in `line` behind an amber-hot trimmed stroke that
/// draws clockwise from 12 o'clock. Supports an optional centered `label` + `sub`
/// readout (used for the Hub hero "40s / LEFT").
struct Ring: View {
    /// 0.0 - 1.0. Values below 0.02 are clamped so the stroke never disappears.
    let progress: Double
    var size: CGFloat = 54
    var stroke: CGFloat = 4
    var label: String? = nil
    var sub: String? = nil
    /// Override the hot color (useful for tier-based tinting).
    var tint: Color = BrandPalette.amberAccent.hot

    private var clamped: Double { max(0.02, min(1, progress)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(BrandPalette.line, lineWidth: stroke)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)

            if let label {
                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: size > 60 ? 18 : 12, weight: .bold, design: .monospaced))
                        .tracking(-0.02 * size)
                        .foregroundStyle(BrandPalette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let sub {
                        Text(sub)
                            .font(.system(size: 7, weight: .semibold, design: .monospaced))
                            .tracking(1.0)
                            .foregroundStyle(BrandPalette.text.opacity(0.6))
                    }
                }
                .frame(width: size - stroke * 2, height: size - stroke * 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.map { "\($0) \(sub ?? "")" } ?? "Progress \(Int(progress * 100)) percent")
    }
}

#Preview {
    VStack(spacing: 24) {
        Ring(progress: 0.25, size: 36, stroke: 3)
        Ring(progress: 0.5, size: 54, stroke: 4, label: "50%")
        Ring(progress: 0.85, size: 118, stroke: 7, label: "4h", sub: "REMAINING")
    }
    .padding(40)
    .background(BrandPalette.ground)
}
