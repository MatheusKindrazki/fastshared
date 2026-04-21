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
    private var bundleActivities: [String: Activity<BundleUploadAttributes>] = [:]

    // WHY: ActivityKit rejects updates beyond ~5-6 Hz. We throttle to one update every 250ms
    // (4 Hz) per job — well under the limit, imperceptible to humans, and cheap enough that
    // the background URLSession delegate thread stays uncongested.
    private var lastUpdateAt: [UUID: Date] = [:]
    private var lastBundleUpdateAt: [String: Date] = [:]
    private let minUpdateInterval: TimeInterval = 0.25

    public init() {}

    /// Starts the Live Activity immediately when the host process has access
    /// to the widget descriptors (the main app), or defers the request into an
    /// App Group queue when called from a sandboxed extension (share ext,
    /// where `Activity.request` returns but the system has no descriptor to
    /// render — the card never appears on the Dynamic Island). The main app
    /// drains the queue via `drainPendingStarts()` during launch or when
    /// `handleEventsForBackgroundURLSession` wakes it up.
    @discardableResult
    public func startOrDefer(clientJobId: UUID,
                             filename: String,
                             contentType: String,
                             retentionPolicy: String,
                             bytesTotal: Int64) -> String? {
        if Self.isRunningInAppExtension {
            Self.enqueuePending(PendingStart(
                clientJobId: clientJobId,
                filename: filename,
                contentType: contentType,
                retentionPolicy: retentionPolicy,
                bytesTotal: bytesTotal
            ))
            log.info("deferred live activity start for \(clientJobId.uuidString, privacy: .public) (extension — main app will create it)")
            return nil
        }
        return start(
            clientJobId: clientJobId,
            filename: filename,
            contentType: contentType,
            retentionPolicy: retentionPolicy,
            progress: 0,
            bytesTotal: bytesTotal
        )
    }

    /// Creates every Live Activity that a share extension deferred. Call this
    /// from the main app (init + `handleEventsForBackgroundURLSession`). Safe
    /// to call repeatedly; dequeues entries as it consumes them.
    public func drainPendingStarts() {
        let pending = Self.loadPending()
        guard !pending.isEmpty else { return }
        Self.clearPending()
        for req in pending {
            _ = start(
                clientJobId: req.clientJobId,
                filename: req.filename,
                contentType: req.contentType,
                retentionPolicy: req.retentionPolicy,
                progress: 0,
                bytesTotal: req.bytesTotal
            )
        }
        log.info("drained \(pending.count, privacy: .public) pending live-activity starts")
    }

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
        guard let activity = await resolveActivity(clientJobId: clientJobId) else { return }
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
        guard let activity = await resolveActivity(clientJobId: clientJobId) else { return }
        let state = FastSharedActivityAttributes.ContentState(phase: .completed,
                                                              progress: 1.0,
                                                              bytesSent: 0,
                                                              bytesTotal: 0,
                                                              shortUrl: shortUrl,
                                                              expiresAt: expiresAt)
        // WHY: dismissalPolicy is "when does the system discard the card
        // entirely from the Dynamic Island + lock screen", not "how long is
        // the link valid". The prior wiring used `expiresAt + 5 min`, which
        // for a 24h retention meant the finished pill stuck around for a
        // whole day — the user saw ghost activities for every past upload.
        // We now dismiss ~30 s after success so the celebration is brief
        // and the DI is free for the next upload.
        let dismissAt = Date().addingTimeInterval(30)
        if #available(iOS 16.2, *) {
            let content = ActivityContent(state: state, staleDate: expiresAt)
            await activity.end(content, dismissalPolicy: .after(dismissAt))
        } else {
            await activity.end(using: state, dismissalPolicy: .after(dismissAt))
        }
        activities.removeValue(forKey: clientJobId)
        lastUpdateAt.removeValue(forKey: clientJobId)
    }

    public func finishFailure(clientJobId: UUID, reason: String) async {
        guard let activity = await resolveActivity(clientJobId: clientJobId) else { return }
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

    /// Ends any Live Activity that is still alive from an earlier run of the
    /// app. Call this at main-app launch — the previous session could have
    /// crashed between `start()` and `finishSuccess`, leaving a pill sitting
    /// at 0% forever on the Dynamic Island. We also catch activities that
    /// did reach `.completed` but have a stale dismissalPolicy (e.g. bug in
    /// the old `expiresAt + 5min` code), so historical installs recover on
    /// upgrade. Idempotent — safe to call repeatedly.
    public func sweepStaleActivities() async {
        let all = Activity<FastSharedActivityAttributes>.activities
        guard !all.isEmpty else { return }
        let now = Date()
        var swept = 0
        for activity in all {
            // Anything still claiming to be uploading after 10+ minutes is
            // almost certainly abandoned (Apple background URLSessions that
            // take that long are rare, and even then the next resume would
            // re-open a fresh Activity).
            let state = activity.content.state
            let isStaleUpload = state.phase == .uploading
                && activity.content.staleDate.map { $0 < now } != false
            // Completed/failed pills whose staleDate has passed — finish
            // draining them so the DI slot is free.
            let isFinishedStale = (state.phase == .completed || state.phase == .failed)
                && activity.content.staleDate.map { $0 < now } ?? false
            if isStaleUpload || isFinishedStale {
                if #available(iOS 16.2, *) {
                    await activity.end(nil, dismissalPolicy: .immediate)
                } else {
                    await activity.end(dismissalPolicy: .immediate)
                }
                swept += 1
            }
        }
        if swept > 0 {
            log.info("swept \(swept, privacy: .public) stale live activities on boot")
        }
    }

    // MARK: - Bundle Live Activity

    /// Bundle equivalent of `startOrDefer`. Same extension detection: when
    /// invoked from a sandboxed extension we park the request in App Group
    /// defaults and the main app drains it via `drainPendingBundleStarts()`.
    @discardableResult
    public func startBundleOrDefer(bundleToken: String,
                                   fileCount: Int,
                                   totalBytes: Int64,
                                   filenames: [String],
                                   retentionPolicy: String) -> String? {
        if Self.isRunningInAppExtension {
            Self.enqueuePendingBundle(PendingBundleStart(
                bundleToken: bundleToken,
                fileCount: fileCount,
                totalBytes: totalBytes,
                filenames: filenames,
                retentionPolicy: retentionPolicy
            ))
            log.info("deferred bundle live activity start for \(bundleToken, privacy: .public) (extension)")
            return nil
        }
        return startBundle(
            bundleToken: bundleToken,
            fileCount: fileCount,
            totalBytes: totalBytes,
            filenames: filenames,
            retentionPolicy: retentionPolicy
        )
    }

    public func drainPendingBundleStarts() {
        let pending = Self.loadPendingBundles()
        guard !pending.isEmpty else { return }
        Self.clearPendingBundles()
        for req in pending {
            _ = startBundle(
                bundleToken: req.bundleToken,
                fileCount: req.fileCount,
                totalBytes: req.totalBytes,
                filenames: req.filenames,
                retentionPolicy: req.retentionPolicy
            )
        }
        log.info("drained \(pending.count, privacy: .public) pending bundle live-activity starts")
    }

    @discardableResult
    public func startBundle(bundleToken: String,
                            fileCount: Int,
                            totalBytes: Int64,
                            filenames: [String],
                            retentionPolicy: String) -> String? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.info("Live Activities disabled by user; skipping bundle start for \(bundleToken, privacy: .public)")
            return nil
        }
        if let existing = bundleActivities[bundleToken] {
            return existing.id
        }
        let attributes = BundleUploadAttributes(bundleToken: bundleToken,
                                                fileCount: fileCount,
                                                totalBytes: totalBytes,
                                                filenames: filenames,
                                                retentionPolicy: retentionPolicy)
        let state = BundleUploadAttributes.ContentState(phase: .uploading,
                                                        bytesUploaded: 0,
                                                        progress: 0)
        do {
            let activity: Activity<BundleUploadAttributes>
            if #available(iOS 16.2, *) {
                let content = ActivityContent(state: state, staleDate: nil)
                activity = try Activity.request(attributes: attributes,
                                                content: content,
                                                pushType: nil)
            } else {
                activity = try Activity.request(attributes: attributes,
                                                contentState: state,
                                                pushType: nil)
            }
            bundleActivities[bundleToken] = activity
            lastBundleUpdateAt[bundleToken] = Date()
            log.info("started bundle live activity \(activity.id, privacy: .public) for token \(bundleToken, privacy: .public)")
            return activity.id
        } catch {
            log.error("Bundle Activity.request failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func updateBundleProgress(bundleToken: String,
                                     bytesUploaded: Int64,
                                     totalBytes: Int64,
                                     progress: Double) async {
        guard let activity = await resolveBundleActivity(bundleToken: bundleToken) else { return }
        let now = Date()
        if let last = lastBundleUpdateAt[bundleToken],
           now.timeIntervalSince(last) < minUpdateInterval,
           progress < 1.0 {
            return
        }
        lastBundleUpdateAt[bundleToken] = now
        let state = BundleUploadAttributes.ContentState(phase: .uploading,
                                                        bytesUploaded: bytesUploaded,
                                                        progress: max(0, min(1, progress)))
        if #available(iOS 16.2, *) {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        } else {
            await activity.update(using: state)
        }
    }

    public func finishBundleSuccess(bundleToken: String,
                                    bundleShortUrl: String,
                                    expiresAt: Date) async {
        guard let activity = await resolveBundleActivity(bundleToken: bundleToken) else { return }
        let state = BundleUploadAttributes.ContentState(phase: .completed,
                                                        bytesUploaded: activity.attributes.totalBytes,
                                                        progress: 1.0,
                                                        bundleShortUrl: bundleShortUrl,
                                                        expiresAt: expiresAt)
        let dismissAt = Date().addingTimeInterval(30)
        if #available(iOS 16.2, *) {
            let content = ActivityContent(state: state, staleDate: expiresAt)
            await activity.end(content, dismissalPolicy: .after(dismissAt))
        } else {
            await activity.end(using: state, dismissalPolicy: .after(dismissAt))
        }
        bundleActivities.removeValue(forKey: bundleToken)
        lastBundleUpdateAt.removeValue(forKey: bundleToken)
    }

    public func finishBundleFailure(bundleToken: String, reason: String) async {
        guard let activity = await resolveBundleActivity(bundleToken: bundleToken) else { return }
        let state = BundleUploadAttributes.ContentState(phase: .failed,
                                                        bytesUploaded: 0,
                                                        progress: 0,
                                                        errorReason: reason)
        let dismissAt = Date().addingTimeInterval(60)
        if #available(iOS 16.2, *) {
            let content = ActivityContent(state: state, staleDate: dismissAt)
            await activity.end(content, dismissalPolicy: .after(dismissAt))
        } else {
            await activity.end(using: state, dismissalPolicy: .after(dismissAt))
        }
        bundleActivities.removeValue(forKey: bundleToken)
        lastBundleUpdateAt.removeValue(forKey: bundleToken)
    }

    private func resolveBundleActivity(bundleToken: String) async -> Activity<BundleUploadAttributes>? {
        if let cached = bundleActivities[bundleToken] {
            return cached
        }
        for activity in Activity<BundleUploadAttributes>.activities
        where activity.attributes.bundleToken == bundleToken {
            bundleActivities[bundleToken] = activity
            return activity
        }
        return nil
    }

    // MARK: - Extension detection + pending queue

    /// True when this code is running inside an app extension target (share
    /// ext, widget, etc.). Live Activity descriptors are only registered with
    /// the host app's process — from an extension `Activity.request` returns
    /// a handle but the system has nothing to render, so we defer instead.
    private static var isRunningInAppExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    /// Persisted form of a `startOrDefer` call that the share ext couldn't
    /// honor directly. Main app drains these on next launch / wake.
    private struct PendingStart: Codable {
        let clientJobId: UUID
        let filename: String
        let contentType: String
        let retentionPolicy: String
        let bytesTotal: Int64
    }

    /// Bundle counterpart of `PendingStart` — written from the share ext when a
    /// multi-file drop spawns a bundle Activity that the ext can't actually
    /// render. Drained from the main app on launch / wake.
    private struct PendingBundleStart: Codable {
        let bundleToken: String
        let fileCount: Int
        let totalBytes: Int64
        let filenames: [String]
        let retentionPolicy: String
    }

    private static let pendingStartsKey = "liveactivity.pending_starts.v1"
    private static let pendingBundleStartsKey = "liveactivity.pending_bundle_starts.v1"

    private static func appGroupDefaults() -> UserDefaults? {
        UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
    }

    private static func enqueuePending(_ req: PendingStart) {
        guard let defaults = appGroupDefaults() else { return }
        var current = loadPending()
        current.append(req)
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: pendingStartsKey)
        }
    }

    private static func loadPending() -> [PendingStart] {
        guard let defaults = appGroupDefaults(),
              let data = defaults.data(forKey: pendingStartsKey),
              let decoded = try? JSONDecoder().decode([PendingStart].self, from: data)
        else { return [] }
        return decoded
    }

    private static func clearPending() {
        appGroupDefaults()?.removeObject(forKey: pendingStartsKey)
    }

    private static func enqueuePendingBundle(_ req: PendingBundleStart) {
        guard let defaults = appGroupDefaults() else { return }
        var current = loadPendingBundles()
        current.append(req)
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: pendingBundleStartsKey)
        }
    }

    private static func loadPendingBundles() -> [PendingBundleStart] {
        guard let defaults = appGroupDefaults(),
              let data = defaults.data(forKey: pendingBundleStartsKey),
              let decoded = try? JSONDecoder().decode([PendingBundleStart].self, from: data)
        else { return [] }
        return decoded
    }

    private static func clearPendingBundles() {
        appGroupDefaults()?.removeObject(forKey: pendingBundleStartsKey)
    }

    // MARK: - Cross-process resolution

    /// Returns the live `Activity` for this job, consulting the in-memory cache
    /// first and falling back to a system-wide lookup via `Activity.activities`.
    ///
    /// WHY: the activity is typically created inside the share extension
    /// (`UploadService.enqueue → start`). When that process exits, the main
    /// app's `LiveActivityController.shared` is a fresh actor with an empty
    /// `activities` dict — the `BackgroundSessionManager` URLSession delegate
    /// runs in the main app, not the ext, so it would silently no-op on every
    /// progress tick and the Dynamic Island would never update. Re-querying
    /// the system list by `attributes.clientJobId` rebuilds the link.
    private func resolveActivity(clientJobId: UUID) async -> Activity<FastSharedActivityAttributes>? {
        if let cached = activities[clientJobId] {
            return cached
        }
        for activity in Activity<FastSharedActivityAttributes>.activities
        where activity.attributes.clientJobId == clientJobId {
            activities[clientJobId] = activity
            return activity
        }
        return nil
    }
}

#else

/// No-op stub so call sites compile on platforms without ActivityKit (macOS, tvOS, watchOS, Linux).
public actor LiveActivityController {
    public static let shared = LiveActivityController()

    public init() {}

    @discardableResult
    public func startOrDefer(clientJobId: UUID,
                             filename: String,
                             contentType: String,
                             retentionPolicy: String,
                             bytesTotal: Int64) -> String? {
        nil
    }

    public func drainPendingStarts() {}

    public func sweepStaleActivities() async {}

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

    @discardableResult
    public func startBundleOrDefer(bundleToken: String,
                                   fileCount: Int,
                                   totalBytes: Int64,
                                   filenames: [String],
                                   retentionPolicy: String) -> String? {
        nil
    }

    public func drainPendingBundleStarts() {}

    @discardableResult
    public func startBundle(bundleToken: String,
                            fileCount: Int,
                            totalBytes: Int64,
                            filenames: [String],
                            retentionPolicy: String) -> String? {
        nil
    }

    public func updateBundleProgress(bundleToken: String,
                                     bytesUploaded: Int64,
                                     totalBytes: Int64,
                                     progress: Double) async {}

    public func finishBundleSuccess(bundleToken: String,
                                    bundleShortUrl: String,
                                    expiresAt: Date) async {}

    public func finishBundleFailure(bundleToken: String, reason: String) async {}
}

#endif
