import SwiftUI
import FastSharedCore

struct RootView: View {
    @State private var hasSeenOnboarding: Bool = Self.loadOnboardingFlag()
    @Environment(\.paywallCoordinator) private var paywallCoordinator
    #if os(iOS)
    @State private var screenshotDetector = ScreenshotDetector()
    #endif

    var body: some View {
        @Bindable var coordinator = paywallCoordinator
        return content
            // WHY: anchor the window surface in brand ink. Without this, the
            // WindowGroup's default white backing can flash between scenes and
            // leaks at physical edges (notch column, home indicator, landscape
            // sides) on iPhone. Scene-level `.ignoresSafeArea()` fills still
            // own their own bleed; this guarantees there is never a white band
            // underneath, even during transitions.
            .background(BrandPalette.ground.ignoresSafeArea())
            .sheet(item: $coordinator.pending) { trigger in
                PaywallView(trigger: trigger)
            }
    }

    @ViewBuilder
    private var content: some View {
        if !hasSeenOnboarding {
            OnboardingView(onComplete: {
                Self.persistOnboardingFlag(true)
                hasSeenOnboarding = true
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
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(BrandPalette.textDim)
                        }
                    }
                }
        }
        // WHY: the redesign ships with violet as the default accent; tinting
        // the whole NavigationStack here propagates to system-default chrome
        // (nav back button, toolbar icons, progress views) without touching
        // every child. Existing `BrandPalette.amberAccent` reads are left in
        // place where the semantic is specifically "warm heat point".
        .tint(BrandPalette.accent.hot)
        // WHY: ground the whole window with the brand ink so every pixel outside
        // the safe area (notch/dynamic-island column, home-indicator strip, side
        // margins on landscape) reads as dark — not the default window white. The
        // NavigationStack itself doesn't ignore safe area, so we paint underneath
        // it. Child scenes still set `BrandPalette.ground.ignoresSafeArea()` for
        // their own fills; this is the belt-and-suspenders layer.
        .background(BrandPalette.ground.ignoresSafeArea())
        .preferredColorScheme(.dark)
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
        #else
        NavigationSplitView {
            MacSidebar()
        } detail: {
            HistoryView()
        }
        .tint(BrandPalette.accent.hot)
        .background(BrandPalette.ground)
        .preferredColorScheme(.dark)
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
