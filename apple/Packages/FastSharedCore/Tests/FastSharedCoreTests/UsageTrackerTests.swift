import XCTest
@testable import FastSharedCore

final class UsageTrackerTests: XCTestCase {

    // MARK: - Helpers

    /// Fake clock — returns whatever key tests push into it.
    final class FakeClock: UsageClock, @unchecked Sendable {
        var key: String
        init(_ key: String) { self.key = key }
        func todayKey() -> String { key }
    }

    /// Unique UserDefaults suite per test so writes don't leak between cases.
    private func isolatedDefaults(file: StaticString = #file, line: UInt = #line) -> UserDefaults {
        let name = "dev.kindrazki.fastshared.usage-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            XCTFail("unable to build isolated defaults", file: file, line: line)
            return .standard
        }
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Forces pending write tasks to flush so persistence is observable.
    private func flushWrites() async {
        try? await Task.sleep(nanoseconds: 350_000_000)
    }

    // MARK: - Cases

    func test_initialCount_isZero() async {
        let tracker = UsageTracker(clock: FakeClock("2026-04-19"), defaults: isolatedDefaults())
        let count = await tracker.currentCount()
        XCTAssertEqual(count, 0)
    }

    func test_increment_isMonotonic() async {
        let tracker = UsageTracker(clock: FakeClock("2026-04-19"), defaults: isolatedDefaults())
        let a = await tracker.increment()
        let b = await tracker.increment()
        let c = await tracker.increment()
        XCTAssertEqual([a, b, c], [1, 2, 3])
    }

    func test_persistsAcrossActorRestarts() async {
        let defaults = isolatedDefaults()
        let clock = FakeClock("2026-04-19")
        let first = UsageTracker(clock: clock, defaults: defaults)
        _ = await first.increment()
        _ = await first.increment()
        await flushWrites()

        let second = UsageTracker(clock: clock, defaults: defaults)
        let count = await second.currentCount()
        XCTAssertEqual(count, 2)
    }

    func test_dayRollover_viaInjectedClock() async {
        let clock = FakeClock("2026-04-19")
        let tracker = UsageTracker(clock: clock, defaults: isolatedDefaults())
        _ = await tracker.increment()
        _ = await tracker.increment()
        clock.key = "2026-04-20"
        let newDay = await tracker.currentCount()
        XCTAssertEqual(newDay, 0)
    }

    func test_remaining_forFree_cappedAt3() async {
        let tracker = UsageTracker(clock: FakeClock("2026-04-19"), defaults: isolatedDefaults())
        _ = await tracker.increment()
        _ = await tracker.increment()
        let remaining = await tracker.remaining(for: .free)
        XCTAssertEqual(remaining, 1)
    }

    func test_remaining_forPro_returnsUnlimitedSentinel() async {
        let tracker = UsageTracker(clock: FakeClock("2026-04-19"), defaults: isolatedDefaults())
        _ = await tracker.increment()
        let remaining = await tracker.remaining(for: .pro(.monthly))
        XCTAssertEqual(remaining, UsageUnlimited)
    }

    func test_prunesOldKeys() async {
        let defaults = isolatedDefaults()
        let clock = FakeClock("2026-04-19")
        let tracker = UsageTracker(clock: clock, defaults: defaults)
        _ = await tracker.increment()
        // Jump 10 days forward; the old key must be gone after the next read.
        clock.key = "2026-04-29"
        _ = await tracker.currentCount()
        await flushWrites()

        let reloaded = UsageTracker(clock: clock, defaults: defaults)
        let fresh = await reloaded.currentCount()
        XCTAssertEqual(fresh, 0)
        // And the prior day-key shouldn't be counted if we rewind the clock
        // — the prune pass deleted it.
        clock.key = "2026-04-19"
        let restored = await reloaded.currentCount()
        XCTAssertEqual(restored, 0, "old keys must be pruned by prior horizon eviction")
    }
}
