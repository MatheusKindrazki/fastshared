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
                let shouldRun = snap.isPro && snap.caps.allowsCloudSync && toggleOn
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
            RootView()
                .environment(\.apiClient, apiClient)
                .environment(\.uploadService, uploadService)
                .environment(\.uploadOrchestrator, orchestrator)
                .environment(\.clipboard, clipboard)
                .environment(\.subscriptionStore, subscriptionStore)
                .environment(\.paywallCoordinator, paywallCoordinator)
                .modelContainer(store.modelContainer)
        }
        #if os(macOS)
        .windowToolbarStyle(.unified)
        #endif
    }
}

#if canImport(UIKit)
final class IOSAppDelegate: NSObject, UIApplicationDelegate {
    private let log = Logger(subsystem: Log.subsystem, category: "app")

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        log.info("Resuming background URLSession \(identifier, privacy: .public)")
        BackgroundSessionManager.shared.attach(completionHandler: completionHandler, identifier: identifier)
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
