import Foundation
import OSLog

// WHY: ActivityKit is importable on macOS but its public protocols are unavailable there,
// so gate on os(iOS) to keep the type-safe API inside iOS-only builds and provide a no-op
// stub everywhere else.
#if os(iOS)
import ActivityKit

/// Wraps ActivityKit so the rest of the codebase never imports it directly. On platforms
/// without Live Activities (macOS, tvOS, watchOS) a no-op shim is compiled instead.
public actor LiveActivityController {
    public static let shared = LiveActivityController()

    private let log = Logger(subsystem: Log.subsystem, category: "liveActivity")
    private var activities: [UUID: Activity<FastSharedActivityAttributes>] = [:]

    // WHY: ActivityKit rejects updates beyond ~5-6 Hz. We throttle to one update every 250ms
    // (4 Hz) per job — well under the limit, imperceptible to humans, and cheap enough that
    // the background URLSession delegate thread stays uncongested.
    private var lastUpdateAt: [UUID: Date] = [:]
    private let minUpdateInterval: TimeInterval = 0.25

    public init() {}

    @discardableResult
    public func start(clientJobId: UUID,
                      filename: String,
                      contentType: String,
                      retentionPolicy: String,
                      progress: Double = 0,
                      bytesTotal: Int64 = 0) -> String? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.info("Live Activities disabled by user; skipping start for \(clientJobId.uuidString, privacy: .public)")
            return nil
        }
        if let existing = activities[clientJobId] {
            return existing.id
        }
        let attributes = FastSharedActivityAttributes(clientJobId: clientJobId,
                                                      filename: filename,
                                                      contentType: contentType,
                                                      retentionPolicy: retentionPolicy)
        let state = FastSharedActivityAttributes.ContentState(phase: .uploading,
                                                              progress: progress,
                                                              bytesSent: 0,
                                                              bytesTotal: bytesTotal)
        do {
            let activity: Activity<FastSharedActivityAttributes>
            if #available(iOS 16.2, *) {
                let content = ActivityContent(state: state, staleDate: nil)
                activity = try Activity.request(attributes: attributes,
                                                content: content,
                                                pushType: nil)
            } else {
                // WHY: iOS 16.1 API is deprecated but kept for defensive compatibility; our
                // deployment target is iOS 17 so this branch should never execute.
                activity = try Activity.request(attributes: attributes,
                                                contentState: state,
                                                pushType: nil)
            }
            activities[clientJobId] = activity
            lastUpdateAt[clientJobId] = Date()
            log.info("started live activity \(activity.id, privacy: .public) for job \(clientJobId.uuidString, privacy: .public)")
            return activity.id
        } catch {
            log.error("Activity.request failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func updateProgress(clientJobId: UUID,
                               progress: Double,
                               bytesSent: Int64,
                               bytesTotal: Int64) async {
        guard let activity = activities[clientJobId] else { return }
        let now = Date()
        if let last = lastUpdateAt[clientJobId],
           now.timeIntervalSince(last) < minUpdateInterval,
           progress < 1.0 {
            // WHY: always let the terminal update through (progress == 1); rate-limit only mid-flight ticks.
            return
        }
        lastUpdateAt[clientJobId] = now
        let state = FastSharedActivityAttributes.ContentState(phase: .uploading,
                                                              progress: max(0, min(1, progress)),
                                                              bytesSent: bytesSent,
                                                              bytesTotal: bytesTotal)
        if #available(iOS 16.2, *) {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        } else {
            await activity.update(using: state)
        }
    }

    public func finishSuccess(clientJobId: UUID,
                              shortUrl: String,
                              expiresAt: Date) async {
        guard let activity = activities[clientJobId] else { return }
        let state = FastSharedActivityAttributes.ContentState(phase: .completed,
                                                              progress: 1.0,
                                                              bytesSent: 0,
                                                              bytesTotal: 0,
                                                              shortUrl: shortUrl,
                                                              expiresAt: expiresAt)
        if #available(iOS 16.2, *) {
            // WHY: staleDate = expiresAt tells the system the link is no longer valid past
            // expiry; dismissalPolicy keeps the card on-screen for 5 more minutes so the
            // user gets one last glance before it's gone.
            let content = ActivityContent(state: state, staleDate: expiresAt)
            await activity.end(content,
                               dismissalPolicy: .after(expiresAt.addingTimeInterval(300)))
        } else {
            await activity.end(using: state, dismissalPolicy: .after(expiresAt.addingTimeInterval(300)))
        }
        activities.removeValue(forKey: clientJobId)
        lastUpdateAt.removeValue(forKey: clientJobId)
    }

    public func finishFailure(clientJobId: UUID, reason: String) async {
        guard let activity = activities[clientJobId] else { return }
        let state = FastSharedActivityAttributes.ContentState(phase: .failed,
                                                              progress: 0,
                                                              bytesSent: 0,
                                                              bytesTotal: 0,
                                                              errorReason: reason)
        let dismissAt = Date().addingTimeInterval(60)
        if #available(iOS 16.2, *) {
            let content = ActivityContent(state: state, staleDate: dismissAt)
            await activity.end(content, dismissalPolicy: .after(dismissAt))
        } else {
            await activity.end(using: state, dismissalPolicy: .after(dismissAt))
        }
        activities.removeValue(forKey: clientJobId)
        lastUpdateAt.removeValue(forKey: clientJobId)
    }
}

#else

/// No-op stub so call sites compile on platforms without ActivityKit (macOS, tvOS, watchOS, Linux).
public actor LiveActivityController {
    public static let shared = LiveActivityController()

    public init() {}

    @discardableResult
    public func start(clientJobId: UUID,
                      filename: String,
                      contentType: String,
                      retentionPolicy: String,
                      progress: Double = 0,
                      bytesTotal: Int64 = 0) -> String? {
        nil
    }

    public func updateProgress(clientJobId: UUID,
                               progress: Double,
                               bytesSent: Int64,
                               bytesTotal: Int64) async {}

    public func finishSuccess(clientJobId: UUID,
                              shortUrl: String,
                              expiresAt: Date) async {}

    public func finishFailure(clientJobId: UUID, reason: String) async {}
}

#endif
