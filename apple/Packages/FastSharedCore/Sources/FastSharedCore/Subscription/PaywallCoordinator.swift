import SwiftUI
import Observation

/// Presenter for `PaywallView`. One instance per process (main app + share ext
/// instantiate their own). Injected via environment; views attach
/// `.sheet(item: $coordinator.pending) { PaywallView(trigger: $0) }` once at
/// the root.
///
/// WHY `@Observable` `@MainActor`: SwiftUI needs the binding driven from the
/// main actor; `@Observable` provides the granular per-property subscription
/// the iOS 17 `.sheet(item:)` modifier requires.
@MainActor
@Observable
public final class PaywallCoordinator {
    public var pending: PaywallTriggerContext?

    public init() {}

    public func present(_ trigger: PaywallTriggerContext) {
        // WHY: reassigning the same value cycles the sheet; guard so a double-
        // fired trigger (e.g. picker reverts + onChange) doesn't re-present.
        if pending != trigger { pending = trigger }
    }

    public func dismiss() {
        pending = nil
    }
}

/// SwiftUI environment key for the process-scoped `PaywallCoordinator`.
private struct PaywallCoordinatorKey: EnvironmentKey {
    @MainActor static let defaultValue: PaywallCoordinator = PaywallCoordinator()
}

public extension EnvironmentValues {
    var paywallCoordinator: PaywallCoordinator {
        get { self[PaywallCoordinatorKey.self] }
        set { self[PaywallCoordinatorKey.self] = newValue }
    }
}
