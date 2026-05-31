import Foundation
import OSLog
import SwiftData
import CloudKit

// MARK: - Public protocol

public protocol CloudKitSyncEngineProtocol: Sendable {
    func start() async throws
    func stop() async
    var isRunning: Bool { get async }
}

public enum CloudKitSyncEngineError: Error, Sendable, Equatable {
    case notSubscribed
    case notInitialized
}

// MARK: - Kernel abstraction

/// Thin wrapper around `CKSyncEngine` so tests can substitute a recording
/// double. `CKSyncEngine` is final/CloudKit-owned and can't be mocked.
public protocol SyncEngineKernel: AnyObject, Sendable {
    /// Schedules a pending record-zone change the kernel will flush to
    /// CloudKit on its own cadence.
    func addPendingChange(_ change: SyncPendingChange) async
    /// Snapshot of the currently-scheduled pending changes.
    var pending: [SyncPendingChange] { get async }
    /// True once `start()` has succeeded.
    var isRunning: Bool { get async }
    /// Invokes the kernel's start/stop lifecycle.
    func start() async throws
    func stop() async
}

public enum SyncPendingChange: Sendable, Equatable {
    case save(recordName: String)
    case delete(recordName: String)
}

// MARK: - Actor

public final actor CloudKitSyncEngine: CloudKitSyncEngineProtocol {
    public let kernel: SyncEngineKernel
    private let store: SwiftDataStore
    private let subscriptionStore: SubscriptionStoreProtocol
    private let persistenceEvents: PersistenceEventStream
    private let deviceId: UUID
    private let log = Logger(subsystem: Log.subsystem, category: "cloudkit")

    private var started = false
    private var eventsTask: Task<Void, Never>?

    public init(kernel: SyncEngineKernel,
                store: SwiftDataStore,
                subscriptionStore: SubscriptionStoreProtocol,
                deviceId: UUID,
                persistenceEvents: PersistenceEventStream = .shared) {
        self.kernel = kernel
        self.store = store
        self.subscriptionStore = subscriptionStore
        self.deviceId = deviceId
        self.persistenceEvents = persistenceEvents
    }

    public var isRunning: Bool {
        get async { await kernel.isRunning }
    }

    public func start() async throws {
        let snapshot = await subscriptionStore.currentSnapshot()
        guard snapshot.caps.allowsCloudSync else {
            throw CloudKitSyncEngineError.notSubscribed
        }
        guard !started else { return }
        try await kernel.start()
        started = true
        subscribeToPersistenceEvents()
        log.info("CloudKitSyncEngine started for device \(self.deviceId.uuidString, privacy: .public)")
    }

    public func stop() async {
        eventsTask?.cancel()
        eventsTask = nil
        await kernel.stop()
        started = false
        // WHY: NEVER call `.deleteRecord` on downgrade. Apple retains the
        // user's private CloudKit data until they disable iCloud for this app.
        log.info("CloudKitSyncEngine stopped; cloud records retained")
    }

    // MARK: - Event subscription

    private func subscribeToPersistenceEvents() {
        eventsTask?.cancel()
        let kernel = self.kernel
        let events = persistenceEvents.events
        eventsTask = Task { [weak self] in
            for await event in events {
                if Task.isCancelled { break }
                let change: SyncPendingChange
                switch event {
                case .shareLinkInserted(let token), .shareLinkUpdated(let token):
                    change = .save(recordName: token)
                case .shareLinkDeleted(let token):
                    change = .delete(recordName: token)
                }
                await kernel.addPendingChange(change)
                _ = self
            }
        }
    }
}

// MARK: - Production kernel (CKSyncEngine)

/// Production kernel backed by `CKSyncEngine`. Hidden behind the protocol so
/// tests can substitute an in-memory recording double.
///
/// WHY the kernel/adaptor split: `CKSyncEngine` is final + CloudKit-owned and
/// its delegate callback shape changes between iOS 17.0 and 17.4. Pinning the
/// production glue here keeps the rest of `CloudKitSyncEngine` stable.
public final class CKSyncEngineKernel: NSObject, SyncEngineKernel, CKSyncEngineDelegate, @unchecked Sendable {

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let defaults: UserDefaults?
    private let statePersistenceKey = "cksync_state_v1"

    private let store: SwiftDataStore
    private let deviceId: UUID
    private let persistenceEvents: PersistenceEventStream
    private let log = Logger(subsystem: Log.subsystem, category: "cloudkit.kernel")

    private var engine: CKSyncEngine?

    public init(store: SwiftDataStore,
                deviceId: UUID,
                persistenceEvents: PersistenceEventStream = .shared,
                defaults: UserDefaults? = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)) {
        self.container = CKContainer(identifier: ShareLinkRecord.containerID)
        self.database = container.privateCloudDatabase
        self.zoneID = CKRecordZone.ID(zoneName: ShareLinkRecord.zoneName,
                                      ownerName: CKCurrentUserDefaultName)
        self.store = store
        self.deviceId = deviceId
        self.persistenceEvents = persistenceEvents
        self.defaults = defaults
    }

    public var isRunning: Bool {
        get async { engine != nil }
    }

    public func start() async throws {
        guard engine == nil else { return }

        // WHY: CKSyncEngine does NOT auto-create custom record zones.
        // If FastSharedZone doesn't exist on the server, every sync fails
        // with "Zone Not Found" (26/2036). We must provision it first.
        try await ensureZoneExists()

        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: loadSerialization(),
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine

        // WHY: CKSyncEngine does NOT pull existing server records on its own at
        // startup — it only reacts to push notifications and flushes local
        // pending changes. A freshly-installed device therefore never sees the
        // links another device already uploaded (the records sit in CloudKit,
        // unfetched) until a push happens to arrive. Kick an explicit fetch on
        // start so device B pulls device A's history immediately. Best-effort:
        // push-driven sync still covers everything created afterwards.
        Task { [weak engine, log] in
            do {
                try await engine?.fetchChanges()
            } catch {
                log.error("Initial CloudKit fetch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func ensureZoneExists() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        do {
            let saved = try await database.save(zone)
            log.info("CloudKit zone created: \(saved.zoneID.zoneName, privacy: .public)")
        } catch let error as CKError {
            // Zone already exists — harmless, proceed.
            if error.code == .serverRecordChanged || error.code == .zoneNotFound {
                log.info("CloudKit zone already exists or concurrent creation: \(self.zoneID.zoneName, privacy: .public)")
            } else {
                log.error("Failed to create CloudKit zone: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        } catch {
            log.error("Failed to create CloudKit zone: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public func stop() async {
        await engine?.cancelOperations()
        engine = nil
    }

    public var pending: [SyncPendingChange] {
        get async {
            guard let engine else { return [] }
            return engine.state.pendingRecordZoneChanges.compactMap { change in
                switch change {
                case .saveRecord(let id): return .save(recordName: id.recordName)
                case .deleteRecord(let id): return .delete(recordName: id.recordName)
                @unknown default: return nil
                }
            }
        }
    }

    public func addPendingChange(_ change: SyncPendingChange) async {
        guard let engine else { return }
        switch change {
        case .save(let name):
            let recordID = CKRecord.ID(recordName: name, zoneID: zoneID)
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .delete(let name):
            let recordID = CKRecord.ID(recordName: name, zoneID: zoneID)
            engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
        }
    }

    // MARK: - Persistence helpers

    private func loadSerialization() -> CKSyncEngine.State.Serialization? {
        guard let defaults, let data = defaults.data(forKey: statePersistenceKey) else { return nil }
        let decoder = PropertyListDecoder()
        return try? decoder.decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveSerialization(_ serialization: CKSyncEngine.State.Serialization) {
        guard let defaults else { return }
        let encoder = PropertyListEncoder()
        if let data = try? encoder.encode(serialization) {
            defaults.set(data, forKey: statePersistenceKey)
        }
    }

    // MARK: - CKSyncEngineDelegate

    // MARK: - CKSyncEngineDelegate (iOS 17.4+ / macOS 14.4+ async)

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await handleEventCommon(event, syncEngine: syncEngine)
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                          syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] recordID in
            guard let self else { return nil }
            return self.buildRecord(for: recordID)
        }
    }

    // MARK: - CKSyncEngineDelegate (iOS 17.0 / macOS 14.0 sync fallback)
    // WHY: The async handleEvent signature was added in iOS 17.4. On earlier OS
    // versions within our deployment target, CKSyncEngine silently skips the
    // async method, so fetched records are never applied. The sync
    // nextRecordZoneChangeBatch async variant is bridged automatically by the
    // runtime on older OSes, so we only need the sync fallback for handleEvent.

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) {
        Task { await handleEventCommon(event, syncEngine: syncEngine) }
    }

    // MARK: - Common delegate implementation

    private func handleEventCommon(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saveSerialization(update.stateSerialization)
        case .fetchedRecordZoneChanges(let changes):
            await applyFetched(changes)
        case .sentRecordZoneChanges(let sent):
            await handleSentRecordZoneChanges(sent, syncEngine: syncEngine)
        case .accountChange, .fetchedDatabaseChanges, .willFetchChanges, .willFetchRecordZoneChanges,
             .didFetchChanges, .didFetchRecordZoneChanges, .willSendChanges, .didSendChanges,
             .sentDatabaseChanges:
            break
        @unknown default:
            break
        }
    }

    private func handleSentRecordZoneChanges(
        _ sent: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async {
        for failure in sent.failedRecordSaves {
            let code = failure.error.code.rawValue
            log.error("CloudKit save failed for \(failure.record.recordID.recordName, privacy: .public): \(failure.error.localizedDescription, privacy: .public) (code: \(code))")
        }

        // WHY: re-queue failed saves; successful ones need no follow-up.
        // Do NOT re-queue serverRecordChanged conflicts — doing so creates an
        // infinite retry loop because the local record lacks the server's
        // recordChangeTag. Those need conflict resolution (future work).
        let failedSaves = sent.failedRecordSaves.compactMap { failure -> CKSyncEngine.PendingRecordZoneChange? in
            if failure.error.code == .serverRecordChanged {
                log.warning("Skipping re-queue for serverRecordChanged conflict on \(failure.record.recordID.recordName, privacy: .public)")
                return nil
            }
            return .saveRecord(failure.record.recordID)
        }
        if !failedSaves.isEmpty {
            syncEngine.state.add(pendingRecordZoneChanges: failedSaves)
            log.info("Re-queued \(failedSaves.count) failed CloudKit saves")
        }
    }

    private func buildRecord(for recordID: CKRecord.ID) -> CKRecord? {
        let context = store.backgroundContext()
        let token = recordID.recordName
        let descriptor = FetchDescriptor<ShareLinkEntity>(predicate: #Predicate { $0.token == token })
        guard let entity = try? context.fetch(descriptor).first else { return nil }
        return entity.toCKRecord(deviceId: deviceId, in: zoneID)
    }

    private func applyFetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        let context = store.backgroundContext()
        for modification in changes.modifications {
            do {
                let remote = try modification.record.asShareLinkEntity()
                let token = remote.token
                let descriptor = FetchDescriptor<ShareLinkEntity>(predicate: #Predicate { $0.token == token })
                if let existing = try context.fetch(descriptor).first {
                    // WHY: last-write-wins on modificationDate — CloudKit seeds
                    // this on every successful save.
                    existing.assetId = remote.assetId
                    existing.shortURLString = remote.shortURLString
                    existing.expiresAt = remote.expiresAt
                    existing.deleteAfter = remote.deleteAfter
                    existing.linkStatus = remote.linkStatus
                    existing.retentionPolicy = remote.retentionPolicy
                    existing.contentType = remote.contentType
                    existing.sizeBytes = remote.sizeBytes
                    existing.originalFilename = remote.originalFilename
                    existing.revokedAt = remote.revokedAt
                    existing.isFavorited = remote.isFavorited
                    existing.visibilityRaw = remote.visibilityRaw
                    existing.lastAccessedAt = remote.lastAccessedAt
                    existing.accessCount = remote.accessCount
                    existing.isBundle = remote.isBundle
                } else {
                    context.insert(remote)
                }
                try context.save()
            } catch {
                log.error("applyFetched modification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        for deletion in changes.deletions {
            let token = deletion.recordID.recordName
            let descriptor = FetchDescriptor<ShareLinkEntity>(predicate: #Predicate { $0.token == token })
            if let entities = try? context.fetch(descriptor) {
                for entity in entities {
                    context.delete(entity)
                }
                try? context.save()
            }
        }
    }
}
