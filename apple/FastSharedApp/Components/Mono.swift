import SwiftUI
import FastSharedCore

/// Monospace label atom — SwiftUI port of `Mono()` from `design/screens.jsx`.
///
/// Uppercase mono caption with tight size + wide tracking. The design language
/// leans on this a lot: section headers, status badges, metadata keys.
struct Mono: View {
    private let text: String
    private let size: CGFloat
    private let track: CGFloat
    private let color: Color
    private let weight: Font.Weight

    /// - Parameters:
    ///   - text: Uppercased inside the view.
    ///   - size: Point size. Defaults to 11 (hub section headers).
    ///   - track: Tracking in points; maps from the JSX `track` int by dividing by 10 and multiplying by size ratio.
    ///   - color: Defaults to `textDim`.
    ///   - weight: Defaults to `.semibold` (JSX default is 600).
    init(_ text: String,
         size: CGFloat = 11,
         track: CGFloat = 1.6,
         color: Color = BrandPalette.textDim,
         weight: Font.Weight = .semibold) {
        self.text = text
        self.size = size
        self.track = track
        self.color = color
        self.weight = weight
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: weight, design: .monospaced))
            .tracking(track)
            .foregroundStyle(color)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        Mono("next to expire")
        Mono("manifest · 05", color: BrandPalette.accent.hot)
        Mono("sorted: urgency", size: 10, color: BrandPalette.textFaint)
        Mono("no account · no sign-in · no trace", size: 10, track: 1.4, color: BrandPalette.textFaint)
    }
    .padding(32)
    .background(BrandPalette.ground)
}
