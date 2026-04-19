import SwiftUI
import FastSharedCore

/// The massive headline number at the top of the hub. "How many links are still out there."
///
/// Displays:
///  - A monumental numeric glyph (SF Pro Display, 144–180pt).
///  - A small caps label underneath in SF Mono.
///  - A sidecar: the closest expiry pill + an "urgency" spark bar.
struct HeroCountMetric: View {
    let count: Int
    let nearestRemaining: TimeInterval?
    let referenceDate: Date

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 144
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                numeral
                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: 16) {
                captionColumn
                Spacer(minLength: 0)
                sidecar
            }

            UrgencySparkBar(remaining: nearestRemaining)
                .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 12)
        .onAppear {
            withAnimation(BrandMotion.transition) { appeared = true }
        }
    }

    private var numeral: some View {
        Text("\(count)")
            .font(.system(size: numeralSize, weight: .bold, design: .default))
            .tracking(-numeralSize * 0.06)
            .foregroundStyle(BrandPalette.milk)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .contentTransition(.numericText())
            .animation(BrandMotion.transition, value: count)
    }

    private var captionColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ACTIVE · EXPIRING · SOON")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(BrandPalette.milk.opacity(0.55))
            Text(count == 1 ? "link in the wild" : "links in the wild")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(BrandPalette.milk.opacity(0.7))
        }
    }

    @ViewBuilder
    private var sidecar: some View {
        if let nearestRemaining {
            VStack(alignment: .trailing, spacing: 4) {
                Text("SOONEST")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(BrandPalette.milk.opacity(0.45))
                ExpiryPill(remaining: nearestRemaining, date: referenceDate, size: .small)
            }
        } else {
            EmptyView()
        }
    }
}
