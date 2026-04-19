import SwiftUI
import FastSharedCore

/// SwiftUI environment key for the app-scoped `SubscriptionStore`.
///
/// Default value is an in-memory fallback that reports Free — SwiftUI previews
/// and screenshots don't need to talk to StoreKit.
private struct SubscriptionStoreKey: EnvironmentKey {
    static let defaultValue: SubscriptionStoreProtocol = NoopSubscriptionStore()
}

public extension EnvironmentValues {
    var subscriptionStore: SubscriptionStoreProtocol {
        get { self[SubscriptionStoreKey.self] }
        set { self[SubscriptionStoreKey.self] = newValue }
    }
}

/// Default store for SwiftUI previews. Always free; no-ops on every call.
public final actor NoopSubscriptionStore: SubscriptionStoreProtocol {
    public init() {}

    public nonisolated var snapshotStream: AsyncStream<SubscriptionSnapshot> {
        AsyncStream { continuation in
            continuation.yield(.free)
            continuation.finish()
        }
    }

    public func currentSnapshot() async -> SubscriptionSnapshot { .free }
    public func refreshProducts() async throws {}
    public func purchase(_ productID: String) async throws -> PurchaseOutcome { .userCancelled }
    public func restore() async throws {}
    public func syncCurrentEntitlements() async {}
}
