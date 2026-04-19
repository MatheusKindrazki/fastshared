import Foundation
import OSLog

/// `unlimited` sentinel for callers that want an `Int` but actually mean
/// "no cap" (e.g. remaining for Pro). Display code must render `∞` — never
/// this number verbatim.
public let UsageUnlimited: Int = .max

/// Clock abstraction for UTC day-key generation. Production defaults to the
/// system clock; tests substitute a fake to exercise the day-rollover path.
public protocol UsageClock: Sendable {
    /// Returns `yyyy-MM-dd` in UTC for the clock's current moment.
    func todayKey() -> String
}

/// Production UTC clock — the only shared instance used outside tests.
public struct SystemUsageClock: UsageClock {
    public init() {}

    public func todayKey() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let y = components.year ?? 1970
        let m = components.month ?? 1
        let d = components.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}

public protocol UsageTrackerProtocol: Sendable {
    /// Upload count for the current UTC day.
    func currentCount() async -> Int
    /// Increments the current UTC day's count by 1 and returns the new value.
    func increment() async -> Int
    /// Remaining uploads for the given tier (`UsageUnlimited` for Pro / unlimited caps).
    func remaining(for tier: Tier) async -> Int
    #if DEBUG
    /// Debug-only: wipes all counters. Never used in production builds.
    func reset() async
    #endif
}

/// UTC-day-keyed usage counter persisted into the App Group defaults so main
/// app and share extension share state.
///
/// WHY UTC: a Pro user whose account travels across devices must not
/// double-count uploads when crossing timezones. Local-midnight display is a
/// UI concern and lives in `SettingsView`'s caps row (Part 6).
/// WHY UserDefaults (not SwiftData): the share extension needs this read/write
/// path before SwiftData is wired; debounced writes through a single-flight
/// task coalesce bursts (e.g. 10-image share drop).
public final actor UsageTracker: UsageTrackerProtocol {

    /// Shared singleton. Composition roots inject an alternate instance only
    /// in tests.
    public static let shared = UsageTracker()

    public static let defaultsKey = "usage_counts_v1"

    private let clock: UsageClock
    private let defaults: UserDefaults?
    private let log = Logger(subsystem: Log.subsystem, category: "usage")

    private var loaded = false
    private var counts: [String: Int] = [:]
    private var pendingWrite: Task<Void, Never>?

    /// Retention window (UTC days). Prunes keys older than this on every mutation.
    private static let retentionDays = 3

    public init(clock: UsageClock = SystemUsageClock(),
                defaults: UserDefaults? = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)) {
        self.clock = clock
        self.defaults = defaults
    }

    // MARK: - Public API

    public func currentCount() async -> Int {
        await loadIfNeeded()
        prune()
        return counts[clock.todayKey()] ?? 0
    }

    @discardableResult
    public func increment() async -> Int {
        await loadIfNeeded()
        let key = clock.todayKey()
        let next = (counts[key] ?? 0) + 1
        counts[key] = next
        prune()
        scheduleWrite()
        return next
    }

    public func remaining(for tier: Tier) async -> Int {
        await loadIfNeeded()
        guard let cap = tier.caps.dailyUploadLimit else { return UsageUnlimited }
        let used = counts[clock.todayKey()] ?? 0
        return max(0, cap - used)
    }

    #if DEBUG
    public func reset() async {
        counts = [:]
        scheduleWrite()
    }
    #endif

    // MARK: - Persistence

    private func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        guard let defaults, let data = defaults.data(forKey: Self.defaultsKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([String: Int].self, from: data)
            counts = decoded
        } catch {
            log.error("load decode failed: \(error.localizedDescription, privacy: .public)")
            counts = [:]
        }
    }

    /// Coalesces bursty increments into at most one write per 250 ms.
    private func scheduleWrite() {
        pendingWrite?.cancel()
        let snapshot = counts
        let defaults = defaults
        pendingWrite = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.writeNow(snapshot: snapshot, defaults: defaults)
        }
    }

    private func writeNow(snapshot: [String: Int], defaults: UserDefaults?) {
        guard let defaults else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: Self.defaultsKey)
        } catch {
            log.error("write encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func prune() {
        guard !counts.isEmpty else { return }
        let today = clock.todayKey()
        let alive = alivenessHorizon(today: today)
        counts = counts.filter { key, _ in alive.contains(key) }
    }

    /// Returns the set of UTC day keys considered "fresh" (today + lookback).
    private func alivenessHorizon(today: String) -> Set<String> {
        guard let todayDate = Self.parseDayKey(today) else { return Set([today]) }
        var result: Set<String> = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        for offset in 0..<Self.retentionDays {
            if let date = calendar.date(byAdding: .day, value: -offset, to: todayDate) {
                let comps = calendar.dateComponents([.year, .month, .day], from: date)
                let key = String(format: "%04d-%02d-%02d",
                                 comps.year ?? 1970,
                                 comps.month ?? 1,
                                 comps.day ?? 1)
                result.insert(key)
            }
        }
        return result
    }

    private static func parseDayKey(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }
}

// MARK: - Subscription gate error

/// Raised by the upload pre-flight pipeline when a Free-tier cap is reached.
/// UI callers map these into a `PaywallTriggerContext` before presenting.
public enum SubscriptionGate: Error, Sendable, Equatable {
    case dailyCapReached(used: Int, cap: Int)
    case fileTooLarge(sizeBytes: Int64, cap: Int64)
    case retentionTooLong(requestedSeconds: TimeInterval, cap: TimeInterval)
    case cloudSyncRequiresPro
}
