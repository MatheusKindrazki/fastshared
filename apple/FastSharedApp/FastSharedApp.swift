import SwiftUI
import SwiftData
import FastSharedCore
import OSLog

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

@main
struct FastSharedApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(IOSAppDelegate.self) private var appDelegate
    #elseif canImport(AppKit)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif

    private let store: SwiftDataStore
    private let apiClient: APIClientProtocol
    private let uploadService: UploadServiceProtocol
    private let orchestrator: UploadOrchestrator
    private let clipboard: ClipboardProtocol
    private let subscriptionStore: SubscriptionStore
    private let cloudKitEngine: CloudKitSyncEngine
    @State private var paywallCoordinator = PaywallCoordinator()

    init() {
        let store = SwiftDataStore.shared
        let keychain = KeychainStore(service: AppGroupConfig.identifier, accessGroup: AppGroupConfig.keychainAccessGroup)
        let tokenStore = DeviceTokenStore(keychain: keychain)
        let apiClient = APIClient(tokenStore: tokenStore)
        let clipboard = Clipboard.make()
        let orchestrator = UploadOrchestrator(apiClient: apiClient, store: store, clipboard: clipboard)
        let background = BackgroundSessionManager.shared
        background.bind(orchestrator: orchestrator, store: store)
        background.prewarm()
        let subscriptionStore = SubscriptionStore(apiClient: apiClient)
        let uploadService = UploadService(apiClient: apiClient,
                                          store: store,
                                          tokenStore: tokenStore,
                                          background: background,
                                          orchestrator: orchestrator,
                                          subscriptionStore: subscriptionStore)
        // WHY: device-stable UUID — per-install is fine, we only use this to
        // tag CloudKit records with the origin. Stored in App Group defaults.
        let deviceId = Self.loadOrCreateDeviceSyncId()
        let kernel = CKSyncEngineKernel(store: store, deviceId: deviceId)
        let cloudKitEngine = CloudKitSyncEngine(
            kernel: kernel,
            store: store,
            subscriptionStore: subscriptionStore,
            deviceId: deviceId
        )

        self.store = store
        self.apiClient = apiClient
        self.uploadService = uploadService
        self.orchestrator = orchestrator
        self.clipboard = clipboard
        self.subscriptionStore = subscriptionStore
        self.cloudKitEngine = cloudKitEngine

        // WHY: App Intents (FastShareScreenshotIntent) need access to the same UploadService the
        // views use, but they run outside the SwiftUI environment. Install once on launch so the
        // Action Button / Siri / Back Tap paths can resolve it synchronously via the locator.
        Task { await UploadServiceLocator.shared.install(uploadService) }
        Task { await SubscriptionStoreLocator.shared.install(subscriptionStore) }
        Task { await orchestrator.resumeUnfinishedJobs() }
        // WHY: share extensions can't create Live Activities themselves —
        // they have no widget descriptor visibility, so `Activity.request`
        // there produces an orphan that never renders. The extension parks
        // the request in an App Group queue; the main app drains it here
        // on cold launch (and again on background wake via the app delegate).
        Task { await LiveActivityController.shared.drainPendingStarts() }
        // M4: same drain loop for bundle activities (multi-file share-ext drops).
        Task { await LiveActivityController.shared.drainPendingBundleStarts() }
        // Sweep Live Activities from previous runs — prior builds left the
        // dismissal policy at `expiresAt + 5 min` so successful uploads kept
        // their pill on the Dynamic Island for up to 24 h. Clean those up on
        // boot so the DI isn't permanently occupied.
        Task { await LiveActivityController.shared.sweepStaleActivities() }
        Task {
            await subscriptionStore.start()
            try? await subscriptionStore.refreshProducts()
            await subscriptionStore.syncCurrentEntitlements()
            // B6.3: cold-launch replay so server is never behind device-local
            // Apple state (e.g. a Family upgrade on another device).
            await subscriptionStore.replayEntitlementsVerification()
        }
        // Run state tracker for CloudKit — (isPro && allowsCloudSync && toggle).
        Task { [cloudKitEngine, subscriptionStore] in
            let defaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
            for await snap in subscriptionStore.snapshotStream {
                let toggleOn = defaults?.object(forKey: "cloud_sync_enabled_v1") as? Bool ?? true
                let shouldRun = snap.caps.allowsCloudSync && toggleOn
                let running = await cloudKitEngine.isRunning
                if shouldRun && !running {
                    try? await cloudKitEngine.start()
                } else if !shouldRun && running {
                    await cloudKitEngine.stop()
                }
            }
        }
    }

    /// Lazily materialized per-install device UUID stored in the App Group. Used to
    /// tag CloudKit records with the originating device (avoids echo on self-fetch).
    private static func loadOrCreateDeviceSyncId() -> UUID {
        let key = "cksync_device_id_v1"
        let defaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
        if let raw = defaults?.string(forKey: key), let existing = UUID(uuidString: raw) {
            return existing
        }
        let fresh = UUID()
        defaults?.set(fresh.uuidString, forKey: key)
        return fresh
    }

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            // WHY: redesigned macOS window — `LibraryView` is the shared
            // sidebar+table surface (also used on iPad regular). Replaces the
            // legacy `MacCompanionView` companion layout.
            LibraryView()
                .environment(\.apiClient, apiClient)
                .environment(\.uploadService, uploadService)
                .environment(\.uploadOrchestrator, orchestrator)
                .environment(\.clipboard, clipboard)
                .environment(\.subscriptionStore, subscriptionStore)
                .environment(\.paywallCoordinator, paywallCoordinator)
                .modelContainer(store.modelContainer)
            #else
            RootView()
                .environment(\.apiClient, apiClient)
                .environment(\.uploadService, uploadService)
                .environment(\.uploadOrchestrator, orchestrator)
                .environment(\.clipboard, clipboard)
                .environment(\.subscriptionStore, subscriptionStore)
                .environment(\.paywallCoordinator, paywallCoordinator)
                .modelContainer(store.modelContainer)
                // WHY: the share extension hands off via `fastshared://pending-upload`
                // (see `ShareViewController.handoffToMainApp`). Receiving the
                // URL here launches + foregrounds the main app so `enqueue`
                // runs in the process that owns the Live Activity widget
                // descriptors — which is the whole reason for the hop.
                .onOpenURL { url in
                    processPendingShareUploads(trigger: url, service: uploadService, paywallCoordinator: paywallCoordinator)
                }
                .task {
                    // Cold launch (scene appears, not via URL). Cover the case
                    // where the share ext parked items but the `open` call
                    // couldn't foreground us yet — next time the user opens
                    // the app we still drain the queue.
                    processPendingShareUploads(trigger: nil, service: uploadService, paywallCoordinator: paywallCoordinator)
                }
            #endif
        }
        #if os(macOS)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 720)
        #endif

        #if os(macOS)
        MenuBarExtra("FastShared", systemImage: "paperplane.fill") {
            MacMenuBarView()
                .environment(\.apiClient, apiClient)
                .environment(\.uploadService, uploadService)
                .environment(\.uploadOrchestrator, orchestrator)
                .environment(\.clipboard, clipboard)
                .environment(\.subscriptionStore, subscriptionStore)
                .modelContainer(store.modelContainer)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

#if canImport(UIKit)
final class IOSAppDelegate: NSObject, UIApplicationDelegate {
    private let log = Logger(subsystem: Log.subsystem, category: "app")

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // WHY: CKSyncEngine uses push notifications to trigger real-time sync
        // when records change on another device. Without this, cross-device sync
        // only happens on launch / foreground, causing multi-minute delays.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        log.info("Resuming background URLSession \(identifier, privacy: .public)")
        BackgroundSessionManager.shared.attach(completionHandler: completionHandler, identifier: identifier)
        // Drain any Live Activities queued by the share extension before it
        // died — the main app is the only process with the widget descriptors,
        // so the Activity has to be created (and later updated) here.
        Task { await LiveActivityController.shared.drainPendingStarts() }
        Task { await LiveActivityController.shared.drainPendingBundleStarts() }
    }
}
#endif

#if canImport(AppKit)
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: Log.subsystem, category: "app")

    func application(_ application: NSApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        log.info("Resuming background URLSession \(identifier, privacy: .public)")
        BackgroundSessionManager.shared.attach(completionHandler: completionHandler, identifier: identifier)
    }
}
#endif

private struct APIClientKey: EnvironmentKey {
    static let defaultValue: APIClientProtocol = APIClient(tokenStore: DeviceTokenStore(keychain: KeychainStore(service: AppGroupConfig.identifier, accessGroup: AppGroupConfig.keychainAccessGroup)))
}

private struct UploadServiceKey: EnvironmentKey {
    static let defaultValue: UploadServiceProtocol? = nil
}

private struct UploadOrchestratorKey: EnvironmentKey {
    static let defaultValue: UploadOrchestrator? = nil
}

private struct ClipboardKey: EnvironmentKey {
    static let defaultValue: ClipboardProtocol = Clipboard.make()
}

extension EnvironmentValues {
    var apiClient: APIClientProtocol {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
    var uploadService: UploadServiceProtocol? {
        get { self[UploadServiceKey.self] }
        set { self[UploadServiceKey.self] = newValue }
    }
    var uploadOrchestrator: UploadOrchestrator? {
        get { self[UploadOrchestratorKey.self] }
        set { self[UploadOrchestratorKey.self] = newValue }
    }
    var clipboard: ClipboardProtocol {
        get { self[ClipboardKey.self] }
        set { self[ClipboardKey.self] = newValue }
    }
}

/// Drains the share-extension handoff queue and kicks off `enqueue` in this
/// (main app) process so the Live Activity can bind to the widget.
///
/// Safe to call repeatedly — `PendingShareUploadQueue.drain` wipes the queue
/// before returning, and duplicate calls observe nothing. Runs as a detached
/// Task so the SwiftUI scene's `.onOpenURL` / `.task` callers don't block.
private func processPendingShareUploads(
    trigger: URL?,
    service: UploadServiceProtocol,
    paywallCoordinator: PaywallCoordinator
) {
    if let trigger, trigger.scheme != "fastshared" { return }
    let pending = PendingShareUploadQueue.drain()
    guard !pending.isEmpty else { return }
    Task.detached { [paywallCoordinator] in
        for item in pending {
            do {
                let policy = RetentionPolicy(rawValue: item.retentionPolicyRaw) ?? .default
                _ = try await service.enqueue(
                    stagedURL: item.stagedURL,
                    contentType: item.contentType,
                    originalFilename: item.originalFilename,
                    retentionPolicy: policy
                )
            } catch let gate as SubscriptionGate {
                await MainActor.run {
                    switch gate {
                    case .dailyCapReached(let used, let cap):
                        paywallCoordinator.present(.dailyCapReached(used: used, cap: cap))
                    case .fileTooLarge(let size, _):
                        paywallCoordinator.present(.largeFileRequested(sizeBytes: size))
                    case .retentionTooLong:
                        let fallback = RetentionPolicy(rawValue: item.retentionPolicyRaw) ?? .default
                        paywallCoordinator.present(.longRetentionRequested(policy: fallback))
                    case .cloudSyncRequiresPro:
                        paywallCoordinator.present(.cloudSyncRequested)
                    }
                }
            } catch let api as APIError {
                if case .paymentRequired(let code, _) = api {
                    await MainActor.run {
                        paywallCoordinator.present(.serverForced(errorCode: code))
                    }
                }
                // Other APIErrors: already logged by the service; leave the
                // user's queue drained so the share ext doesn't re-fire on
                // next open.
            } catch {
                // Surface only via OSLog — the service / orchestrator already
                // marks the job failed and will show the failure card.
            }
        }
    }
}
