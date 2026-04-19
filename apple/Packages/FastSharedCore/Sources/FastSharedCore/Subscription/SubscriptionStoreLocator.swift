import Foundation
import FastSharedCore

/// Share-extension-friendly locator for the app-scoped `SubscriptionStore`.
///
/// The share extension runs in a separate process and can't see the main app's
/// SwiftUI environment. Its bootstrap instantiates a second `SubscriptionStore`
/// (same cache, same App Group) and installs it here; paywall triggers resolve
/// it synchronously without re-booting StoreKit for every request.
public actor SubscriptionStoreLocator {
    public static let shared = SubscriptionStoreLocator()
    private var store: SubscriptionStoreProtocol?

    public func install(_ store: SubscriptionStoreProtocol) {
        self.store = store
    }

    public func current() throws -> SubscriptionStoreProtocol {
        guard let store else { throw NotInstalled() }
        return store
    }

    public struct NotInstalled: Error, LocalizedError {
        public var errorDescription: String? {
            "FastShared subscription store isn't initialized yet — open the app once."
        }
    }
}
