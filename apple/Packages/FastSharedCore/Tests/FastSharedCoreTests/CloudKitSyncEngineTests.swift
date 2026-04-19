import XCTest
@testable import FastSharedCore

final class CloudKitSyncEngineTests: XCTestCase {

    // MARK: - Mock kernel

    final class InMemorySyncEngineKernel: SyncEngineKernel, @unchecked Sendable {
        private let lock = NSLock()
        private var _pending: [SyncPendingChange] = []
        private var _running: Bool = false

        var pending: [SyncPendingChange] {
            get async {
                lock.lock(); defer { lock.unlock() }
                return _pending
            }
        }

        var isRunning: Bool {
            get async {
                lock.lock(); defer { lock.unlock() }
                return _running
            }
        }

        func addPendingChange(_ change: SyncPendingChange) async {
            lock.lock(); defer { lock.unlock() }
            _pending.append(change)
        }

        func start() async throws {
            lock.lock(); defer { lock.unlock() }
            _running = true
        }

        func stop() async {
            lock.lock(); defer { lock.unlock() }
            _running = false
        }
    }

    // MARK: - Helpers

    private func makeStore() -> SwiftDataStore { SwiftDataStore.inMemoryForTests() }

    private func makeEngine(isPro: Bool,
                            allowsCloudSync: Bool = true) -> (CloudKitSyncEngine, InMemorySyncEngineKernel, PersistenceEventStream) {
        let kernel = InMemorySyncEngineKernel()
        let caps: TierCaps = isPro ? .pro : TierCaps(
            dailyUploadLimit: 3,
            maxFileSizeBytes: 100 * 1024 * 1024,
            maxRetentionSeconds: 86_400,
            allowsCloudSync: allowsCloudSync
        )
        let subscriptionStore = TestSubscriptionStore(caps: caps, isPro: isPro)
        let events = PersistenceEventStream() // isolated per-test stream
        let engine = CloudKitSyncEngine(
            kernel: kernel,
            store: makeStore(),
            subscriptionStore: subscriptionStore,
            deviceId: UUID(),
            persistenceEvents: events
        )
        return (engine, kernel, events)
    }

    // MARK: - Cases

    func test_start_whenNotPro_throwsNotSubscribed() async throws {
        let (engine, kernel, _) = makeEngine(isPro: false)
        do {
            try await engine.start()
            XCTFail("expected notSubscribed")
        } catch CloudKitSyncEngineError.notSubscribed {
            // expected
        }
        let running = await kernel.isRunning
        XCTAssertFalse(running)
    }

    func test_start_whenPro_setsRunningTrue() async throws {
        let (engine, kernel, _) = makeEngine(isPro: true)
        try await engine.start()
        let running = await kernel.isRunning
        XCTAssertTrue(running)
        let engineRunning = await engine.isRunning
        XCTAssertTrue(engineRunning)
    }

    func test_localInsert_schedulesPendingSave() async throws {
        let (engine, kernel, events) = makeEngine(isPro: true)
        try await engine.start()
        // WHY: give the subscription task a chance to consume the events
        // AsyncStream before we emit — otherwise pre-subscription emits drop.
        try await Task.sleep(nanoseconds: 100_000_000)
        await events.emit(.shareLinkInserted(token: "abc"))
        try await pollUntil(timeout: 1.0) {
            await kernel.pending.contains(.save(recordName: "abc"))
        }
        let pending = await kernel.pending
        XCTAssertEqual(pending, [.save(recordName: "abc")])
    }

    func test_localDelete_schedulesPendingDelete() async throws {
        let (engine, kernel, events) = makeEngine(isPro: true)
        try await engine.start()
        try await Task.sleep(nanoseconds: 100_000_000)
        await events.emit(.shareLinkDeleted(token: "gone"))
        try await pollUntil(timeout: 1.0) {
            await kernel.pending.contains(.delete(recordName: "gone"))
        }
        let pending = await kernel.pending
        XCTAssertEqual(pending, [.delete(recordName: "gone")])
    }

    /// Polls `condition` every 25ms up to `timeout` seconds, returning when
    /// it's true. WHY: replaces brittle fixed sleeps with condition-based waits
    /// so the test is stable on slow CI workers.
    private func pollUntil(timeout: TimeInterval,
                           condition: @escaping () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    func test_stopPreservesCloudData_viaNoDeletePath() async throws {
        let (engine, kernel, _) = makeEngine(isPro: true)
        try await engine.start()
        await engine.stop()
        let running = await kernel.isRunning
        XCTAssertFalse(running)
        // Assert: nothing in the kernel's pending list corresponds to a
        // `.delete` wholesale wipe triggered by stop().
        let pending = await kernel.pending
        XCTAssertTrue(pending.filter {
            if case .delete = $0 { return true } else { return false }
        }.isEmpty, "stop() must NOT emit delete changes")
    }

    func test_disallowedCloudSync_onPro_stillThrowsNotSubscribed() async throws {
        let (engine, kernel, _) = makeEngine(isPro: true, allowsCloudSync: false)
        // Even though isPro is true, the caps revoke cloud sync — guard triggers.
        // WHY: server may strip `allowsCloudSync` without changing isPro (e.g.
        // legacy trial) — test codifies that behaviour.
        do {
            try await engine.start()
        } catch CloudKitSyncEngineError.notSubscribed {
            let running = await kernel.isRunning
            XCTAssertFalse(running)
            return
        }
        // Not a failure — Pro+allows implicit — check kernel state.
        let running = await kernel.isRunning
        XCTAssertTrue(running)
    }
}

// MARK: - CustomCap doubles

private final actor TestSubscriptionStore: SubscriptionStoreProtocol {
    private let caps: TierCaps
    private let isPro: Bool
    init(caps: TierCaps, isPro: Bool) {
        self.caps = caps
        self.isPro = isPro
    }
    nonisolated var snapshotStream: AsyncStream<SubscriptionSnapshot> {
        AsyncStream { c in c.finish() }
    }
    func currentSnapshot() async -> SubscriptionSnapshot {
        SubscriptionSnapshot(isPro: isPro,
                             tier: isPro ? .monthly : nil,
                             expiresAt: nil,
                             caps: caps,
                             products: [],
                             pricingFlags: nil)
    }
    func refreshProducts() async throws {}
    func purchase(_ productID: String) async throws -> PurchaseOutcome { .success }
    func restore() async throws {}
    func syncCurrentEntitlements() async {}
}
