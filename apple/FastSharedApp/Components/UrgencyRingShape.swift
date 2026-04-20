import SwiftUI
import FastSharedCore

/// Urgency progress ring — used on every share row and in the countdown hero.
///
/// Renders a circular track at `urgencyCalm` opacity-15 with a foreground arc
/// trimmed to `progress` (0.0–1.0) painted in the urgency color that matches
/// the current progress band. The foreground arc has a rounded cap.
///
/// - Parameters:
///   - progress: Fraction of time remaining (1.0 = fresh, 0.0 = expired).
///   - size:     Outer diameter in points. Default 44.
///   - stroke:   Track and arc line width in points. Default 4.
struct UrgencyRing: View {
    var progress: Double      // 0.0 - 1.0
    var size: CGFloat = 44
    var stroke: CGFloat = 4

    var body: some View {
        let clamped = max(0.02, min(1.0, progress))
        let tier = tierForProgress(clamped)
        let color = tier.urgencyColor
        ZStack {
            Circle()
                .stroke(BrandPalette.urgencyCalm.opacity(0.15), lineWidth: stroke)
                .frame(width: size, height: size)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    private func tierForProgress(_ p: Double) -> ExpiryTier {
        if p < 0.1 { return .underOneMinute }
        if p < 0.3 { return .underOneHour }
        if p < 0.7 { return .underOneDay }
        return .forever
    }
}

#Preview("UrgencyRing — states") {
    HStack(spacing: 20) {
        UrgencyRing(progress: 0.05)
        UrgencyRing(progress: 0.20)
        UrgencyRing(progress: 0.50)
        UrgencyRing(progress: 1.00)
    }
    .padding(32)
    .background(BrandPalette.ground)
    .preferredColorScheme(.dark)
}
