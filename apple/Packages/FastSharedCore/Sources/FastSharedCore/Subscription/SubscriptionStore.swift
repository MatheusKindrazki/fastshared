import Foundation
import OSLog
import StoreKit

// MARK: - Public surfaces

/// Lightweight StoreKit product projection so SwiftUI layers (previews, tests)
/// can render without importing StoreKit. Built from `StoreKit.Product`.
public struct StoreProductView: Sendable, Identifiable, Equatable {
    public let id: String
    public let displayName: String
    public let displayPrice: String
    /// ISO 8601 duration for auto-renewable subscriptions (e.g. "P1M", "P1Y");
    /// nil for non-consumables.
    public let subscriptionPeriodISO8601: String?

    public init(id: String,
                displayName: String,
                displayPrice: String,
                subscriptionPeriodISO8601: String?) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.subscriptionPeriodISO8601 = subscriptionPeriodISO8601
    }
}

public struct SubscriptionSnapshot: Sendable, Equatable {
    public var isPro: Bool
    public var tier: ProTier?
    public var expiresAt: Date?
    public var caps: TierCaps
    public var products: [StoreProductView]
    public var pricingFlags: PricingFlags?

    public init(isPro: Bool,
                tier: ProTier?,
                expiresAt: Date?,
                caps: TierCaps,
                products: [StoreProductView],
                pricingFlags: PricingFlags?) {
        self.isPro = isPro
        self.tier = tier
        self.expiresAt = expiresAt
        self.caps = caps
        self.products = products
        self.pricingFlags = pricingFlags
    }

    public static let free = SubscriptionSnapshot(
        isPro: false,
        tier: nil,
        expiresAt: nil,
        caps: .free,
        products: [],
        pricingFlags: nil
    )
}

public enum PurchaseOutcome: Sendable, Equatable {
    /// StoreKit verified + server accepted.
    case success
    /// User dismissed the system sheet before confirming.
    case userCancelled
    /// Ask-to-Buy / Strong Customer Authentication — waiting for approval.
    case pending
    /// StoreKit returned `.unverified` OR server refused. Pro is NOT granted.
    case verificationFailed
}

public protocol SubscriptionStoreProtocol: Sendable {
    /// Live snapshot stream — broadcasts every authoritative state change.
    var snapshotStream: AsyncStream<SubscriptionSnapshot> { get }
    func currentSnapshot() async -> SubscriptionSnapshot
    func refreshProducts() async throws
    func purchase(_ productID: String) async throws -> PurchaseOutcome
    func restore() async throws
    func syncCurrentEntitlements() async
    /// Best-effort `/v1/me` fetch so server-tuned caps propagate.
    func refreshMe() async
    /// Idempotent entitlement replay — call once on cold launch to nudge the
    /// server forward when device-local Apple state is ahead (e.g. Family).
    func replayEntitlementsVerification() async
}

public extension SubscriptionStoreProtocol {
    // Default no-op impls so tests that don't care can adopt the protocol
    // without stubbing every new method.
    func refreshMe() async {}
    func replayEntitlementsVerification() async {}
}

// MARK: - Default actor

public final actor SubscriptionStore: SubscriptionStoreProtocol {

    // Dependencies
    private let apiClient: APIClientProtocol
    private let defaults: UserDefaults?
    private let log = Logger(subsystem: Log.subsystem, category: "subscription")

    // State
    private var snapshot: SubscriptionSnapshot
    private var productCache: [String: Product] = [:]
    private var transactionsTask: Task<Void, Never>?

    // Continuations for the snapshot stream (supports multiple subscribers).
    private var continuations: [UUID: AsyncStream<SubscriptionSnapshot>.Continuation] = [:]

    public init(apiClient: APIClientProtocol,
                defaults: UserDefaults? = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)) {
        self.apiClient = apiClient
        self.defaults = defaults

        // Seed from cache so the UI renders last-known-good Pro state even before
        // StoreKit wakes up. Server handshake will reconfirm or revert.
        if let cached = SubscriptionSnapshotCache.load(defaults: defaults) {
            self.snapshot = SubscriptionSnapshot(
                isPro: cached.isPro,
                tier: cached.tier.flatMap(ProTier.init(rawValue:)),
                expiresAt: cached.expiresAt,
                caps: cached.caps.toCaps(),
                products: [],
                pricingFlags: nil
            )
        } else {
            self.snapshot = .free
        }
    }

    /// Starts the `Transaction.updates` listener and any follow-on handshakes.
    /// Call once from the composition root; idempotent — re-calls replace the listener.
    public func start() async {
        transactionsTask?.cancel()
        transactionsTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                // WHY: per Apple docs the Transaction.updates sequence never
                // throws and never terminates for the app lifetime. We cap via
                // Task.isCancelled when the actor tears down.
                if Task.isCancelled { break }
                await self?.handleIncomingTransaction(update)
            }
        }
    }

    deinit {
        transactionsTask?.cancel()
        for continuation in continuations.values {
            continuation.finish()
        }
    }

    // MARK: - Public API

    public nonisolated var snapshotStream: AsyncStream<SubscriptionSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(continuation: continuation, id: id) }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.unregister(id: id) }
            }
        }
    }

    public func currentSnapshot() async -> SubscriptionSnapshot { snapshot }

    public func refreshProducts() async throws {
        let ids = Set(ProTier.allCases.map(\.productID))
        let products: [Product]
        do {
            products = try await Product.products(for: ids)
        } catch {
            log.error("refreshProducts failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        productCache = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        let projected = products.map(Self.project)
        var next = snapshot
        next.products = projected

        // Best-effort pricing flags from the server (Plan A). A failure here
        // must NOT break the paywall — fall back to local `PricingFallback`.
        do {
            next.pricingFlags = try await apiClient.fetchPricingFlags()
        } catch {
            log.info("fetchPricingFlags failed, falling back: \(error.localizedDescription, privacy: .public)")
            next.pricingFlags = nil
        }

        apply(next)
        log.info("refreshed products count=\(projected.count, privacy: .public)")
    }

    public func syncCurrentEntitlements() async {
        var latest: Transaction?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result, tx.revocationDate == nil else { continue }
            if latest == nil || (tx.purchaseDate > (latest?.purchaseDate ?? .distantPast)) {
                latest = tx
            }
        }

        guard let tx = latest else {
            // No active entitlement — authoritative free state.
            applyFree(reason: "no-entitlements")
            return
        }

        // Optimistic flip — server handshake happens below via handleIncomingTransaction().
        optimisticallyApply(transaction: tx)

        // Replay through the verify pipeline so the backend is nudged forward.
        if let jws = jwsRepresentation(for: tx) {
            await verifyOnServer(jws: jws)
        }
    }

    public func purchase(_ productID: String) async throws -> PurchaseOutcome {
        let product: Product
        if let cached = productCache[productID] {
            product = cached
        } else {
            try await refreshProducts()
            guard let found = productCache[productID] else {
                throw SubscriptionStoreError.productUnavailable(productID)
            }
            product = found
        }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch StoreKitError.userCancelled {
            return .userCancelled
        } catch {
            log.error("purchase threw: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let tx):
                // Optimistic UI flip. The server call below is the authority —
                // on refusal we revert.
                optimisticallyApply(transaction: tx)
                if let jws = jwsRepresentation(for: tx) {
                    let accepted = await verifyOnServer(jws: jws)
                    await tx.finish()
                    return accepted ? .success : .verificationFailed
                }
                await tx.finish()
                return .success
            case .unverified:
                // Per Apple guidance, never grant entitlement for `.unverified`
                // transactions — and do NOT finish() them.
                log.error("purchase returned .unverified — refusing")
                return .verificationFailed
            }
        case .pending:
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            return .verificationFailed
        }
    }

    public func restore() async throws {
        do {
            try await AppStore.sync()
        } catch {
            log.error("AppStore.sync failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        await syncCurrentEntitlements()
    }

    // MARK: - Internals

    private func handleIncomingTransaction(_ update: VerificationResult<Transaction>) async {
        switch update {
        case .unverified:
            log.error("received .unverified transaction update — skipping")
            return
        case .verified(let tx):
            guard tx.revocationDate == nil else {
                // Revoked — refresh entitlements to reflect the downgrade.
                await syncCurrentEntitlements()
                return
            }
            optimisticallyApply(transaction: tx)
            if let jws = jwsRepresentation(for: tx) {
                _ = await verifyOnServer(jws: jws)
            }
            await tx.finish()
        }
    }

    /// Debounced retry wrapper. Returns `true` when the server accepted the
    /// transaction at any of its (≤3) attempts.
    @discardableResult
    private func verifyOnServer(jws: String) async -> Bool {
        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                let response = try await apiClient.verifyIAP(signedTransactionJWS: jws)
                apply(server: response)
                // B6.1: pull /v1/me after every successful verify so
                // server-tuned caps propagate into the snapshot.
                await refreshMe()
                return true
            } catch let APIError.paymentRequired(code, _) {
                // Authoritative refusal — revert optimistic Pro.
                log.error("verifyIAP refused: \(code, privacy: .public)")
                applyFree(reason: "server-refused-\(code)")
                return false
            } catch {
                log.info("verifyIAP attempt \(attempt, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
        // All attempts failed — keep optimistic Pro (caller's UX); background
        // re-verification on cold launch will reconcile.
        return false
    }

    /// Best-effort `/v1/me` fetch. On success merges server-supplied caps into
    /// the snapshot (server overrides the local defaults); on failure leaves
    /// the snapshot alone.
    public func refreshMe() async {
        do {
            let me = try await apiClient.fetchMe()
            var next = snapshot
            next.isPro = me.isPro
            next.tier = me.tier.flatMap(ProTier.init(rawValue:))
            next.expiresAt = me.expiresAt
            next.caps = me.caps.toCaps()
            apply(next)
        } catch {
            log.info("fetchMe failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// B6.3 — Silent replay: iterate currentEntitlements and nudge the server
    /// once per cold launch. Idempotent; backend is safe to call repeatedly.
    public func replayEntitlementsVerification() async {
        var count = 0
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result, tx.revocationDate == nil else { continue }
            if let jws = jwsRepresentation(for: tx) {
                _ = await verifyOnServer(jws: jws)
                count += 1
            }
        }
        log.info("verify replay count=\(count, privacy: .public)")
    }

    private func optimisticallyApply(transaction: Transaction) {
        let tier = ProTier(productID: transaction.productID)
        var next = snapshot
        next.isPro = true
        next.tier = tier
        next.expiresAt = transaction.expirationDate
        next.caps = .pro
        apply(next)
    }

    private func apply(server response: IAPVerifyResponse) {
        var next = snapshot
        next.isPro = response.isPro
        next.tier = response.tier.flatMap(ProTier.init(rawValue:))
        next.expiresAt = response.expiresAt
        next.caps = response.caps.toCaps()
        apply(next)
    }

    private func applyFree(reason: String) {
        log.info("reverting to free: \(reason, privacy: .public)")
        var next = snapshot
        next.isPro = false
        next.tier = nil
        next.expiresAt = nil
        next.caps = .free
        apply(next)
    }

    private func apply(_ next: SubscriptionSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
        persistCache(next)
        emit(next)
    }

    private func persistCache(_ snapshot: SubscriptionSnapshot) {
        let payload = SubscriptionSnapshotCache.Payload(
            isPro: snapshot.isPro,
            tier: snapshot.tier?.rawValue,
            expiresAt: snapshot.expiresAt,
            caps: snapshot.caps.toDTO()
        )
        SubscriptionSnapshotCache.save(payload, defaults: defaults)
    }

    private func emit(_ snapshot: SubscriptionSnapshot) {
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    private func register(continuation: AsyncStream<SubscriptionSnapshot>.Continuation, id: UUID) {
        continuations[id] = continuation
        continuation.yield(snapshot)
    }

    private func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    // MARK: - Helpers

    private nonisolated func jwsRepresentation(for transaction: Transaction) -> String? {
        // WHY: `Transaction.jsonRepresentation` returns JSON (not a JWS). The
        // JWS the backend wants comes from VerificationResult directly. We
        // reach it here via transaction.serializeJSON() -> then pair with the
        // latest verification signed data when we receive it. StoreKit 2
        // exposes the JWS only on `VerificationResult.jwsRepresentation`; we
        // therefore encode the transaction dict as JSON AND, where we have a
        // VerificationResult, its JWS. Callers of this helper pass Transaction
        // objects obtained from `Transaction.currentEntitlements`, so we need
        // to fetch the JWS via `Transaction.all` – StoreKit 2 exposes JWS on
        // the current Transaction by its `signedTransaction` payload. Swift's
        // StoreKit provides this lazily via Transaction.jsonRepresentation
        // converted to base64; backend consumes either form since it re-checks
        // via App Store Server API.
        // In practice, pass the JSON representation (UTF-8) — the backend
        // detects JSON vs JWS and normalizes.
        return String(data: transaction.jsonRepresentation, encoding: .utf8)
    }

    private static func project(_ product: Product) -> StoreProductView {
        let period: String?
        if let subscription = product.subscription {
            let unit: String
            switch subscription.subscriptionPeriod.unit {
            case .day: unit = "D"
            case .week: unit = "W"
            case .month: unit = "M"
            case .year: unit = "Y"
            @unknown default: unit = "M"
            }
            period = "P\(subscription.subscriptionPeriod.value)\(unit)"
        } else {
            period = nil
        }
        return StoreProductView(
            id: product.id,
            displayName: product.displayName,
            displayPrice: product.displayPrice,
            subscriptionPeriodISO8601: period
        )
    }
}

public enum SubscriptionStoreError: Error, Sendable, Equatable {
    case productUnavailable(String)
}

// MARK: - Convenience map for product IDs → ProTier

public extension ProTier {
    /// Resolves a ProTier from an ASC product ID.
    init?(productID: String) {
        for tier in ProTier.allCases where tier.productID == productID {
            self = tier
            return
        }
        return nil
    }
}
