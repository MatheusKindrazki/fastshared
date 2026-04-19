import SwiftUI
import FastSharedCore

/// 4-up retention segmented picker that renders lock icons on gated options
/// for Free-tier users and reverts the selection when one is tapped, firing a
/// paywall trigger via the `onPaywall` closure.
///
/// The picker always shows `RetentionPolicy.shareable` — tapping a locked
/// option is how users discover Pro, so hiding them is a regression in
/// discoverability.
public struct GatedRetentionPicker: View {
    @Binding public var selection: RetentionPolicy
    public let tier: Tier
    public let onPaywall: (PaywallTriggerContext) -> Void

    public init(selection: Binding<RetentionPolicy>,
                tier: Tier,
                onPaywall: @escaping (PaywallTriggerContext) -> Void) {
        self._selection = selection
        self.tier = tier
        self.onPaywall = onPaywall
    }

    public var body: some View {
        let accent = BrandPalette.amberAccent
        let options = RetentionPolicy.shareable

        return HStack(spacing: 6) {
            ForEach(options, id: \.self) { policy in
                let selected = selection == policy
                let gated = isGated(policy)

                Button {
                    if gated {
                        // WHY: don't mutate the binding on a gated tap; if we
                        // did, SwiftUI would fire `.onChange` downstream even
                        // though nothing persisted. Route directly to paywall.
                        onPaywall(.longRetentionRequested(policy: policy))
                    } else {
                        selection = policy
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(shortLabel(for: policy))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(selected ? Color(red: 0.07, green: 0.02, blue: 0.04) : BrandPalette.textDim)
                        if gated {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(BrandPalette.textDim)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected ? accent.hot : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: policy, gated: gated))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BrandPalette.ground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(BrandPalette.line, lineWidth: 1)
                )
        )
    }

    private func isGated(_ policy: RetentionPolicy) -> Bool {
        policy.ttlSeconds > tier.caps.maxRetentionSeconds
    }

    private func shortLabel(for policy: RetentionPolicy) -> String {
        switch policy {
        case .oneHour: return "1h"
        case .oneDay: return "24h"
        case .oneWeek: return "1w"
        case .oneMonth: return "1mo"
        default: return policy.displayName
        }
    }

    private func accessibilityLabel(for policy: RetentionPolicy, gated: Bool) -> String {
        // TODO(i18n)
        let base = policy.displayName
        return gated ? "\(base), Pro only" : base
    }
}
