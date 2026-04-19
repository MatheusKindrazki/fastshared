import SwiftUI
import FastSharedCore

/// The manifest header at the top of the hub. "How many links can still be opened?"
///
/// Displays:
///  - A compact product title.
///  - Active link count as the primary metric.
///  - The closest expiry and the signature transfer rail.
struct HeroCountMetric: View {
    let count: Int
    let nearestRemaining: TimeInterval?
    let referenceDate: Date

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 82
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                titleBlock
                Spacer(minLength: 0)
                retentionBadge
            }

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    numeral
                    Text(count == 1 ? "live link" : "live links")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BrandPalette.dust)
                }
                Spacer(minLength: 0)
                sidecar
            }

            UrgencySparkBar(remaining: nearestRemaining)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BrandPalette.line.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: BrandPalette.ink.opacity(0.08), radius: 24, y: 14)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 12)
        .onAppear {
            withAnimation(BrandMotion.transition) { appeared = true }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(BrandPalette.amber)
                Text("FastShared")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.3)
            }
            Text("Temporary links, ready to paste.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(BrandPalette.ink.opacity(0.62))
        }
    }

    private var numeral: some View {
        Text("\(count)")
            .font(.system(size: numeralSize, weight: .bold, design: .default))
            .tracking(-numeralSize * 0.05)
            .foregroundStyle(BrandPalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .contentTransition(.numericText())
            .animation(BrandMotion.transition, value: count)
    }

    private var retentionBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .bold))
            Text("24h default")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(BrandPalette.amber)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(BrandPalette.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var sidecar: some View {
        if let nearestRemaining {
            VStack(alignment: .trailing, spacing: 4) {
                Text("NEXT EXPIRY")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(BrandPalette.dust)
                ExpiryPill(remaining: nearestRemaining, date: referenceDate, size: .small)
            }
        } else {
            EmptyView()
        }
    }
}
