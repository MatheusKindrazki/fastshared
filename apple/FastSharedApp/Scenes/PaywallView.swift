import SwiftUI
import FastSharedCore

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Full-screen modal paywall. Presented via `PaywallCoordinator` from every
/// upsell moment: daily cap hit, cloud-sync toggle (Free), long-retention
/// selection, large-file pre-flight, or a server-forced 402.
///
/// Layout follows the design package `design/screens.jsx` → `Paywall()`:
/// warm sphere, trigger-specific hero line, three tier cards, restore button,
/// footer. All copy is English with `TODO(i18n)` markers. Surfaces use HIG
/// semantic colors; accents (amber, urgency) still come from `BrandPalette`.
struct PaywallView: View {
    let trigger: PaywallTriggerContext

    @Environment(\.subscriptionStore) private var subscriptionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var snapshot: SubscriptionSnapshot = .free
    @State private var purchasing: String?
    @State private var restoring: Bool = false
    @State private var banner: Banner?
    // Diagnostic — flips true once the initial refreshProducts round-trips,
    // and `loadError` captures whatever StoreKit reported. Lets us show a
    // concrete empty state (with the real reason) instead of a forever
    // skeleton when ASC isn't returning products.
    @State private var didAttemptLoad: Bool = false
    @State private var loadError: String?

    private enum Banner: Equatable {
        case pending
        case error(String)
    }

    var body: some View {
        ZStack {
            // HIG semantic ground — adapts to light/dark; no hard-coded
            // dark canvas gradient. Tier cards provide their own surface.
            Color.sysGroupedBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    hero
                    tierCards
                    restoreRow
                    footer
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .dynamicTypeSize(.xSmall ... .accessibility3)
            }
            .scrollIndicators(.hidden)

            if let banner {
                bannerView(banner)
                    .padding()
            }
        }
        .foregroundStyle(Color.sysLabel)
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .task {
            snapshot = await subscriptionStore.currentSnapshot()
            // WHY: subscribe to live snapshot updates so the CTA reflects
            // the moment `/v1/iap/verify` confirms and we can dismiss.
            for await next in subscriptionStore.snapshotStream {
                snapshot = next
                if next.isPro, purchasing != nil {
                    purchasing = nil
                    handlePurchaseSuccess()
                }
            }
        }
        // WHY: kick an explicit product refresh on paywall open. The app-init
        // refresh may have fired before the network was ready or before ASC
        // had the products live; re-running here gives the user a retry
        // surface AND flips `didAttemptLoad` so the UI can stop showing a
        // skeleton forever when the catalog is legitimately empty.
        .task {
            do {
                try await subscriptionStore.refreshProducts()
                loadError = nil
            } catch {
                loadError = (error as? LocalizedError)?.errorDescription
                    ?? String(describing: error)
            }
            snapshot = await subscriptionStore.currentSnapshot()
            didAttemptLoad = true
        }
    }

    // MARK: - Header

    private var header: some View {
        // Brand accent unified on violet.
        let accent = BrandPalette.accent
        return HStack(alignment: .top) {
            HStack(spacing: 8) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 1.0, green: 0.965, blue: 0.878), accent.hot],
                            center: UnitPoint(x: 0.35, y: 0.30),
                            startRadius: 0, endRadius: 12
                        )
                    )
                    .frame(width: 20, height: 20)
                (
                    Text("fastshared")
                        .foregroundStyle(Color.sysLabel)
                    + Text(".pro")
                        .foregroundStyle(accent.hot)
                )
                .font(.system(size: 15, weight: .bold))
                .tracking(-0.3)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("FastShared Pro")

            Spacer()

            Button {
                dismiss()
            } label: {
                // TODO(i18n): close paywall label
                Text("Not now")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.sysSecondaryLabel)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .stroke(Color.sysSeparator, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Close paywall")
            .accessibilityHint("Dismisses the upgrade screen")
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            // TODO(i18n): hero mono ledger
            Text(heroMono)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(BrandPalette.accentHot)

            // TODO(i18n): hero headline
            Text(heroHeadline)
                .font(.system(size: 32, weight: .bold))
                .tracking(-1.2)
                .foregroundStyle(Color.sysLabel)
                .fixedSize(horizontal: false, vertical: true)

            // TODO(i18n): hero subhead
            Text(heroSubhead)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.sysSecondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var heroMono: String {
        switch trigger {
        case .dailyCapReached: return "DAILY LIMIT REACHED"
        case .cloudSyncRequested: return "SYNC ACROSS DEVICES"
        case .longRetentionRequested: return "EXTENDED RETENTION"
        case .largeFileRequested: return "LARGE FILES"
        case .serverForced: return "UPGRADE REQUIRED"
        }
    }

    private var heroHeadline: String {
        // TODO(i18n)
        switch trigger {
        case .dailyCapReached(let used, let cap):
            return "You've used \(used) of \(cap) Free uploads today."
        case .cloudSyncRequested:
            return "Sync your links across all your devices."
        case .longRetentionRequested:
            return "Pick the retention that matches the work."
        case .largeFileRequested(let sizeBytes):
            let human = ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
            return "\(human) is bigger than the Free limit."
        case .serverForced:
            return "Upgrade to keep going."
        }
    }

    private var heroSubhead: String {
        // TODO(i18n)
        switch trigger {
        case .dailyCapReached:
            return "Upgrade to Pro for unlimited uploads, larger files, and cross-device history."
        case .cloudSyncRequested:
            return "Pro mirrors your link history to your private iCloud — no extra setup."
        case .longRetentionRequested:
            return "Pro supports up to 30-day retention. Free tops out at 24 hours."
        case .largeFileRequested:
            return "Pro raises the cap to 5 GB per file and keeps the same one-gesture flow."
        case .serverForced:
            return "Your session hit a Pro-only limit on the server. Unlock the full flow here."
        }
    }

    // MARK: - Tier cards

    private var tierCards: some View {
        VStack(spacing: 12) {
            if didAttemptLoad && snapshot.products.isEmpty {
                productsUnavailableCard
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(ProTier.allCases, id: \.self) { tier in
                        card(for: tier)
                    }
                }
                VStack(spacing: 12) {
                    ForEach(ProTier.allCases, id: \.self) { tier in
                        card(for: tier)
                    }
                }
            }
        }
    }

    /// Shown inline above the tier cards when StoreKit returned zero products
    /// — makes the "silent skeleton" state diagnosable without the Console.
    private var productsUnavailableCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BrandPalette.urgencyCritical)
                Text("Pro products aren't available yet")
                    .font(.system(size: 15, weight: .semibold))
            }
            Text(loadError
                 ?? "StoreKit returned 0 of 3 products for this App Store account. Usually means the Paid Apps Agreement is pending, the product IDs in App Store Connect don't match, or the catalog hasn't propagated yet (5–30 min after save).")
                .font(.system(size: 13))
                .foregroundStyle(Color.sysSecondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            Text("Expecting: red.fastsha.pro.monthly, .annual, .lifetime")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.sysTertiaryLabel)
            Button {
                Task {
                    didAttemptLoad = false
                    do { try await subscriptionStore.refreshProducts(); loadError = nil }
                    catch { loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error) }
                    snapshot = await subscriptionStore.currentSnapshot()
                    didAttemptLoad = true
                }
            } label: {
                Text("Try again")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BrandPalette.urgencyCritical.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(BrandPalette.urgencyCritical.opacity(0.35), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func card(for tier: ProTier) -> some View {
        if let product = snapshot.products.first(where: { $0.id == tier.productID }) {
            PaywallTierCard(
                product: product,
                tier: tier,
                features: features(for: tier),
                badge: badge(for: tier),
                isLoading: purchasing == tier.productID,
                reduceMotion: reduceMotion,
                onPurchase: {
                    performPurchase(productID: tier.productID)
                }
            )
        } else {
            // Products may still be loading — render a placeholder so the
            // layout doesn't jump.
            PaywallTierCard(
                product: StoreProductView(
                    id: tier.productID,
                    displayName: placeholderDisplayName(for: tier),
                    displayPrice: "—",
                    subscriptionPeriodISO8601: placeholderPeriod(for: tier)
                ),
                tier: tier,
                features: features(for: tier),
                badge: badge(for: tier),
                isLoading: false,
                reduceMotion: reduceMotion,
                onPurchase: {
                    performPurchase(productID: tier.productID)
                }
            )
            .redacted(reason: .placeholder)
        }
    }

    private func placeholderDisplayName(for tier: ProTier) -> String {
        // TODO(i18n)
        switch tier {
        case .monthly: return "FastShared Pro Monthly"
        case .annual: return "FastShared Pro Annual"
        case .lifetime: return "FastShared Pro Lifetime"
        }
    }

    private func placeholderPeriod(for tier: ProTier) -> String? {
        switch tier {
        case .monthly: return "P1M"
        case .annual: return "P1Y"
        case .lifetime: return nil
        }
    }

    private func features(for tier: ProTier) -> [String] {
        // TODO(i18n)
        switch tier {
        case .monthly:
            return [
                "Unlimited daily uploads",
                "Files up to 5 GB",
                "Retention up to 30 days",
                "Cross-device sync"
            ]
        case .annual:
            return [
                "Everything in Monthly",
                "Save ~45% vs monthly",
                "One payment per year",
                "Early access to new features"
            ]
        case .lifetime:
            return [
                "Everything in Monthly",
                "One-time payment",
                "Future Pro features included",
                "Up to 6 Family devices"
            ]
        }
    }

    private func badge(for tier: ProTier) -> PaywallTierCard.CardBadge? {
        switch tier {
        case .monthly:
            return nil
        case .annual:
            return .savePercentage(45)
        case .lifetime:
            // WHY: server flags OR local fallback drive the badge. MVP rule —
            // if `pricingFlags` is nil (Plan A not merged), consult fallback.
            let active: Bool
            let endsAt: Date?
            if let flags = snapshot.pricingFlags {
                active = flags.earlyAccessLifetimeActive
                endsAt = flags.earlyAccessEndsAt
            } else {
                active = FastSharedPricingFallback.lifetimeEarlyAccessActive
                endsAt = FastSharedPricingFallback.lifetimeEarlyAccessEndsAt
            }
            return active ? .earlyAccess(endsAt: endsAt) : nil
        }
    }

    // MARK: - Restore + footer

    private var restoreRow: some View {
        HStack {
            Spacer()
            Button {
                performRestore()
            } label: {
                // TODO(i18n)
                Text(restoring ? "RESTORING…" : "RESTORE PURCHASES")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.sysSecondaryLabel)
            }
            .buttonStyle(.plain)
            .disabled(restoring)
            .accessibilityLabel("Restore purchases")
            .accessibilityHint("Reactivates your existing Pro subscription on this device")
            Spacer()
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text("Subscriptions auto-renew monthly or annually. Cancel anytime in Settings.")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.sysTertiaryLabel)
                .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                Button {
                    openURL(URL(string: "https://fastsha.red/privacy")!)
                } label: {
                    // TODO(i18n)
                    Text("PRIVACY")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Color.sysSecondaryLabel)
                }
                .buttonStyle(.plain)

                Button {
                    openURL(URL(string: "https://fastsha.red/terms")!)
                } label: {
                    // TODO(i18n)
                    Text("TERMS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Color.sysSecondaryLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Banner

    private func bannerView(_ banner: Banner) -> some View {
        // Brand accent unified on violet. `accent.fade` stays pink for error icon.
        let accent = BrandPalette.accent
        return VStack {
            Spacer()
            HStack(spacing: 10) {
                switch banner {
                case .pending:
                    Image(systemName: "hourglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent.hot)
                    // TODO(i18n)
                    Text("Waiting for approval…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.sysLabel)
                case .error(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent.fade)
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.sysLabel)
                }
                Spacer()
                Button {
                    self.banner = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.sysSecondaryLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss banner")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.sysSecondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.sysSeparator, lineWidth: 1)
                    )
            )
        }
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Actions

    private func performPurchase(productID: String) {
        purchasing = productID
        banner = nil
        Task {
            do {
                let outcome = try await subscriptionStore.purchase(productID)
                switch outcome {
                case .success:
                    // handlePurchaseSuccess() fires via snapshotStream; we also
                    // dismiss here in case the stream is slow.
                    handlePurchaseSuccess()
                case .userCancelled:
                    purchasing = nil
                case .pending:
                    purchasing = nil
                    banner = .pending
                case .verificationFailed:
                    purchasing = nil
                    // TODO(i18n)
                    banner = .error("Couldn't verify the purchase. Try again.")
                }
            } catch {
                purchasing = nil
                // TODO(i18n)
                banner = .error(error.localizedDescription)
            }
        }
    }

    private func performRestore() {
        restoring = true
        banner = nil
        Task {
            do {
                try await subscriptionStore.restore()
                restoring = false
                let latest = await subscriptionStore.currentSnapshot()
                if latest.isPro {
                    handlePurchaseSuccess()
                } else {
                    // TODO(i18n)
                    banner = .error("No active subscription found on this Apple ID.")
                }
            } catch {
                restoring = false
                // TODO(i18n)
                banner = .error(error.localizedDescription)
            }
        }
    }

    private func handlePurchaseSuccess() {
        playSuccessHaptic()
        if reduceMotion {
            dismiss()
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                dismiss()
            }
        }
    }

    private func playSuccessHaptic() {
        #if canImport(UIKit) && os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #elseif canImport(AppKit) && os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }
}

// MARK: - Previews

#Preview("Daily cap") {
    PaywallView(trigger: .dailyCapReached(used: 3, cap: 3))
}

#Preview("Cloud sync") {
    PaywallView(trigger: .cloudSyncRequested)
}

#Preview("Long retention") {
    PaywallView(trigger: .longRetentionRequested(policy: .oneWeek))
}

#Preview("Large file") {
    PaywallView(trigger: .largeFileRequested(sizeBytes: 250 * 1024 * 1024))
}

#Preview("Server-forced") {
    PaywallView(trigger: .serverForced(errorCode: "pro_required"))
}
