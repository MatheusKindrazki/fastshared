import SwiftUI
import FastSharedCore

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

struct RootView: View {
    @State private var hasSeenOnboarding: Bool = Self.loadOnboardingFlag()
    @State private var hasCompletedAuth: Bool = AuthState.hasCompletedGate
    @State private var splashDismissed: Bool = false
    @Environment(\.paywallCoordinator) private var paywallCoordinator
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @State private var screenshotDetector = ScreenshotDetector()
    #endif

    // WHY: owned here (not in SignInView) because revocation can fire on any
    // launch once the user is already past the gate — we need a stable store to
    // clear on invalidation.
    private let tokenStore = DeviceTokenStore()

    var body: some View {
        @Bindable var coordinator = paywallCoordinator
        return ZStack {
            content
                // WHY: anchor the window surface in brand ground. Without this,
                // the WindowGroup's default white backing can flash between
                // scenes and leaks at physical edges (notch column, home
                // indicator, landscape sides) on iPhone. Scene-level
                // `.ignoresSafeArea()` fills still own their own bleed; this
                // guarantees there is never a white band underneath, even
                // during transitions.
                .background(groundBackground.ignoresSafeArea())
                .sheet(item: $coordinator.pending) { trigger in
                    PaywallView(trigger: trigger)
                }

            if !splashDismissed {
                SplashView(onComplete: { splashDismissed = true })
                    .transition(.identity)
            }
        }
        // WHY: Apple requires us to detect credential revocation on every app
        // launch (Settings → Apple ID → Sign in with Apple → revoke). We also
        // subscribe to the live notification so a revocation that happens WHILE
        // the app is running is caught too.
        .task { await checkAppleCredentialRevocation() }
        #if canImport(AuthenticationServices)
        .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
            Task { await handleCredentialInvalidated() }
        }
        #endif
    }

    /// Polls Apple for the credential state of the stored Apple user id on
    /// launch. If the credential is `.revoked` or `.notFound`, clear local auth
    /// state so the gate re-appears. Leaves `.transferred` / `.authorized`
    /// untouched — those mean the credential is still valid for this app.
    private func checkAppleCredentialRevocation() async {
        #if canImport(AuthenticationServices)
        guard AuthState.currentMode == .apple,
              let userId = AuthState.appleUserId, !userId.isEmpty else { return }

        let provider = ASAuthorizationAppleIDProvider()
        let state: ASAuthorizationAppleIDProvider.CredentialState = await withCheckedContinuation { continuation in
            provider.getCredentialState(forUserID: userId) { state, _ in
                continuation.resume(returning: state)
            }
        }

        switch state {
        case .revoked, .notFound:
            await handleCredentialInvalidated()
        case .authorized, .transferred:
            break
        @unknown default:
            break
        }
        #endif
    }

    /// Wipe local auth state + device token and force the gate back on next
    /// render. Shared between the launch poll and the revoked-notification
    /// observer so both paths converge on the same teardown.
    @MainActor
    private func handleCredentialInvalidated() async {
        AuthState.reset()
        try? await tokenStore.clear()
        hasCompletedAuth = false
    }

    @ViewBuilder
    private var content: some View {
        if !hasSeenOnboarding {
            OnboardingView(onComplete: {
                Self.persistOnboardingFlag(true)
                hasSeenOnboarding = true
            })
        } else if !hasCompletedAuth {
            SignInView(onComplete: {
                hasCompletedAuth = true
            })
        } else {
            mainContent
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        #if os(iOS)
        NavigationStack {
            HistoryView()
                // WHY: the Friendly redesign owns its own header (BrandLockup +
                // gear). We hide the system nav bar here so the custom header
                // can breathe — navigation destinations still push normally.
                .toolbar(.hidden, for: .navigationBar)
        }
        // WHY: the redesign ships with violet as the default accent; tinting
        // the whole NavigationStack here propagates to system-default chrome
        // (nav back button, toolbar icons, progress views) without touching
        // every child.
        .tint(BrandPalette.accent.hot)
        // WHY: ground the whole window with a HIG-semantic surface so every
        // pixel outside the safe area (notch/dynamic-island column, home-
        // indicator strip, side margins on landscape) reads as system
        // background — adapts to light/dark, no hard-coded cream/ink.
        .background(groundBackground.ignoresSafeArea())
        .overlay(alignment: .top) {
            if let pending = screenshotDetector.pending {
                ScreenshotBanner(
                    pending: pending,
                    onUpload: { screenshotDetector.accept() },
                    onDismiss: { screenshotDetector.dismiss() }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .animation(BrandMotion.transition, value: screenshotDetector.pending?.id)
        .overlay(alignment: .top) {
            if let upload = UploadProgressMonitor.shared.current {
                UploadProgressBanner(upload: upload)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(11)
            }
        }
        .animation(BrandMotion.transition, value: UploadProgressMonitor.shared.current?.id)
        .animation(BrandMotion.transition, value: UploadProgressMonitor.shared.current?.phase)
        #else
        NavigationSplitView {
            MacSidebar()
        } detail: {
            HistoryView()
        }
        .tint(BrandPalette.accent.hot)
        .background(groundBackground)
        .overlay(alignment: .top) {
            if let upload = UploadProgressMonitor.shared.current {
                UploadProgressBanner(upload: upload)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(11)
            }
        }
        .animation(BrandMotion.transition, value: UploadProgressMonitor.shared.current?.id)
        .animation(BrandMotion.transition, value: UploadProgressMonitor.shared.current?.phase)
        #endif
    }

    /// HIG-semantic window ground. Adapts to light/dark automatically; no
    /// hard-coded brand cream/ink.
    private var groundBackground: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    // WHY: the app-group suite is shared with the share extension, so onboarding state is consistent
    // when the user uninstalls/reinstalls the main app but keeps the share extension.
    private static func loadOnboardingFlag() -> Bool {
        onboardingDefaults.bool(forKey: "has_seen_onboarding")
    }

    private static func persistOnboardingFlag(_ value: Bool) {
        onboardingDefaults.set(value, forKey: "has_seen_onboarding")
    }

    private static var onboardingDefaults: UserDefaults {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupPaths.groupIdentifier) != nil,
              let shared = UserDefaults(suiteName: AppGroupPaths.groupIdentifier) else {
            return .standard
        }
        return shared
    }
}

#if os(macOS)
private enum MacSection: Hashable {
    case library
    case settings
}

private struct MacSidebar: View {
    @State private var selection: MacSection? = .library

    var body: some View {
        List(selection: $selection) {
            NavigationLink(value: MacSection.library) {
                Label("Library", systemImage: "tray.full")
            }
            NavigationLink(value: MacSection.settings) {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .navigationDestination(for: MacSection.self) { section in
            switch section {
            case .library: HistoryView()
            case .settings: SettingsView()
            }
        }
        .frame(minWidth: 180)
    }
}
#endif
