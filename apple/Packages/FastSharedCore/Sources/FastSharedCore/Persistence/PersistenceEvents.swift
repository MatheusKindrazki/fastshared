import Foundation

/// Events emitted by any site that mutates `ShareLinkEntity` rows.
///
/// Consumers (primarily `CloudKitSyncEngine`) subscribe via
/// `PersistenceEventStream.shared.events` and translate each event into a
/// `CKSyncEngine.State` pending change. WHY `AsyncStream` and not
/// `NotificationCenter`: cleaner `Sendable` story under strict concurrency —
/// `Notification.userInfo` is not `Sendable`.
public enum PersistenceEvent: Sendable, Equatable {
    case shareLinkInserted(token: String)
    case shareLinkUpdated(token: String)
    case shareLinkDeleted(token: String)
}

/// Process-scoped hub for `PersistenceEvent`. Shared actor so share ext + main
/// app can each have a single consumer / multiple producers.
public actor PersistenceEventStream {
    public static let shared = PersistenceEventStream()

    private var continuations: [UUID: AsyncStream<PersistenceEvent>.Continuation] = [:]

    public init() {}

    /// A fresh subscription. Each caller receives every event emitted after
    /// it connects.
    public nonisolated var events: AsyncStream<PersistenceEvent> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(continuation: continuation, id: id) }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.unregister(id: id) }
            }
        }
    }

    public func emit(_ event: PersistenceEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func register(continuation: AsyncStream<PersistenceEvent>.Continuation,
                          id: UUID) {
        continuations[id] = continuation
    }

    private func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
