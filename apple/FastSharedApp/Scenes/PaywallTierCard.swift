import SwiftUI
import FastSharedCore

/// A single tier card inside `PaywallView`.
///
/// Styled per the redesign: `BrandPalette.paper` fill, `BrandPalette.line`
/// hairline stroke, mono price cadence below the large price. Annual renders
/// an `BrandPalette.arc` gradient stroke to read as the recommended tier.
struct PaywallTierCard: View {

    enum CardBadge: Equatable {
        case savePercentage(Int)
        case earlyAccess(endsAt: Date?)
    }

    let product: StoreProductView
    let tier: ProTier
    let features: [String]
    let badge: CardBadge?
    let isLoading: Bool
    let reduceMotion: Bool
    let onPurchase: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            titleRow
            priceBlock
            featuresList
            ctaButton
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 280, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            cardStroke
        )
        .overlay(alignment: .topTrailing) {
            if let badge {
                badgeView(badge)
                    .padding(10)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOverLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var cardStroke: some View {
        Group {
            if tier == .annual {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BrandPalette.arc, lineWidth: 1.5)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 1)
            }
        }
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(tierDisplayName)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color(.label))
            Spacer(minLength: 0)
        }
    }

    private var tierDisplayName: String {
        // TODO(i18n)
        switch tier {
        case .monthly: return "Monthly"
        case .annual: return "Annual"
        case .lifetime: return "Lifetime"
        }
    }

    private var priceBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(product.displayPrice)
                .font(.largeTitle.monospacedDigit())
                .fontWeight(.bold)
                .tracking(-0.6)
                .foregroundStyle(Color(.label))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(priceCadence)
                .font(.caption.monospaced())
                .foregroundStyle(Color(.tertiaryLabel))
        }
    }

    private var priceCadence: String {
        // TODO(i18n)
        switch product.subscriptionPeriodISO8601 {
        case "P1M": return "per month"
        case "P1Y": return "per year"
        case nil: return "one-time payment"
        default: return product.subscriptionPeriodISO8601 ?? ""
        }
    }

    private var featuresList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(features, id: \.self) { feature in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(BrandPalette.amberAccent.hot)
                    Text(feature)
                        .font(.body)
                        .foregroundStyle(Color(.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var ctaButton: some View {
        let accent = BrandPalette.amberAccent
        return Button(action: onPurchase) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(red: 0.07, green: 0.02, blue: 0.04))
                }
                // TODO(i18n)
                Text(isLoading ? "PROCESSING" : "SUBSCRIBE")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color(red: 0.07, green: 0.02, blue: 0.04))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.hot)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .opacity(isLoading ? 0.7 : 1)
    }

    private func badgeView(_ badge: CardBadge) -> some View {
        Text(badgeText(badge))
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(BrandPalette.ground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(BrandPalette.amberAccent.hot)
            )
    }

    private func badgeText(_ badge: CardBadge) -> String {
        // TODO(i18n)
        switch badge {
        case .savePercentage(let pct):
            return "SAVE \(pct)%"
        case .earlyAccess(let endsAt):
            if let endsAt {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                return "EARLY ACCESS · ENDS \(formatter.string(from: endsAt).uppercased())"
            }
            return "EARLY ACCESS"
        }
    }

    private var voiceOverLabel: String {
        // TODO(i18n): VoiceOver summary combining price + features.
        var parts: [String] = []
        parts.append("\(tierDisplayName) plan")
        parts.append(product.displayPrice)
        parts.append(priceCadence)
        if let badge = badge {
            parts.append(badgeText(badge).replacingOccurrences(of: "·", with: ","))
        }
        parts.append(contentsOf: features)
        parts.append("Double tap to subscribe.")
        return parts.joined(separator: ". ")
    }
}
