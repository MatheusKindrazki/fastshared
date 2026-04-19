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

    init() {
        let store = SwiftDataStore.shared
        let keychain = KeychainStore(service: AppGroupConfig.identifier, accessGroup: AppGroupConfig.keychainAccessGroup)
        let tokenStore = DeviceTokenStore(keychain: keychain)
        let apiClient = APIClient(tokenStore: tokenStore)
        let clipboard = Clipboard.make()
        let orchestrator = UploadOrchestrator(apiClient: apiClient, store: store, clipboard: clipboard)
        let background = BackgroundSessionManager.shared
        background.bind(orchestrator: orchestrator, store: store)
        let uploadService = UploadService(apiClient: apiClient,
                                          store: store,
                                          tokenStore: tokenStore,
                                          background: background,
                                          orchestrator: orchestrator)

        self.store = store
        self.apiClient = apiClient
        self.uploadService = uploadService
        self.orchestrator = orchestrator
        self.clipboard = clipboard

        Task { await orchestrator.resumeUnfinishedJobs() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.apiClient, apiClient)
                .environment(\.uploadService, uploadService)
                .environment(\.uploadOrchestrator, orchestrator)
                .environment(\.clipboard, clipboard)
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
