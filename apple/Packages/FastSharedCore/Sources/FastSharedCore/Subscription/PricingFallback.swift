import Foundation

/// Compile-time fallback for `/v1/pricing-flags` while Plan A is not merged.
///
/// TODO(tech-debt): remove once Plan A ships /v1/pricing-flags and the field
/// is guaranteed non-nil on `SubscriptionSnapshot.pricingFlags`.
public enum FastSharedPricingFallback {
    /// When `true`, the Lifetime tier card renders an "Early Access" badge.
    /// Flip to `false` when the early-access window closes.
    public static let lifetimeEarlyAccessActive: Bool = true

    /// Optional `Date` terminator for "Early Access — ends \(date)" copy. Nil
    /// means the badge renders without a countdown.
    public static let lifetimeEarlyAccessEndsAt: Date? = nil
}
