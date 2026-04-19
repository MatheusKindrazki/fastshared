import Foundation
import OSLog

/// Persists the last-known-good subscription snapshot in the App Group suite so
/// a cold launch post-network-flap still renders Pro immediately (before the
/// StoreKit / server handshake completes).
///
/// Only non-sensitive metadata is cached: `isPro`, tier raw, `expiresAt`, and
/// the caps DTO. No tokens, no PII.
public enum SubscriptionSnapshotCache {
    public static let key = "pro_last_snapshot_v1"

    /// On-disk shape. Top-level type rather than `SubscriptionSnapshot` because
    /// `SubscriptionSnapshot` carries transient product projections that must
    /// never round-trip through the cache.
    public struct Payload: Sendable, Codable, Equatable {
        public let isPro: Bool
        public let tier: String?
        public let expiresAt: Date?
        public let caps: TierCapsDTO

        public init(isPro: Bool, tier: String?, expiresAt: Date?, caps: TierCapsDTO) {
            self.isPro = isPro
            self.tier = tier
            self.expiresAt = expiresAt
            self.caps = caps
        }
    }

    private static let log = Logger(subsystem: Log.subsystem, category: "subscription.cache")

    public static func load(defaults: UserDefaults? = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)) -> Payload? {
        guard let defaults, let data = defaults.data(forKey: key) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Payload.self, from: data)
        } catch {
            log.error("cache decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public static func save(_ payload: Payload,
                            defaults: UserDefaults? = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)) {
        guard let defaults else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            defaults.set(data, forKey: key)
        } catch {
            log.error("cache encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public static func clear(defaults: UserDefaults? = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)) {
        defaults?.removeObject(forKey: key)
    }
}
