import SwiftUI
import FastSharedCore

struct RootView: View {
    @State private var hasSeenOnboarding: Bool = Self.loadOnboardingFlag()

    var body: some View {
        content
            .fullScreenCoverIfAvailable(isPresented: .constant(!hasSeenOnboarding)) {
                OnboardingView(onComplete: {
                    Self.persistOnboardingFlag(true)
                    // WHY: toggling the local state after persisting keeps the `.fullScreenCover` dismissal
                    // in lockstep with the UserDefaults write — the next cold boot also sees the flag.
                    hasSeenOnboarding = true
                })
                .interactiveDismissDisabled(true)
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        NavigationStack {
            HistoryView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
        }
        #else
        NavigationSplitView {
            MacSidebar()
        } detail: {
            HistoryView()
        }
        #endif
    }

    // WHY: the app-group suite is shared with the share extension, so onboarding state is consistent
    // when the user uninstalls/reinstalls the main app but keeps the share extension.
    private static func loadOnboardingFlag() -> Bool {
        UserDefaults(suiteName: AppGroupPaths.groupIdentifier)?.bool(forKey: "has_seen_onboarding") ?? false
    }

    private static func persistOnboardingFlag(_ value: Bool) {
        UserDefaults(suiteName: AppGroupPaths.groupIdentifier)?.set(value, forKey: "has_seen_onboarding")
    }
}

// WHY: macOS has no `fullScreenCover`; present as a modal sheet sized to a card instead.
private extension View {
    @ViewBuilder
    func fullScreenCoverIfAvailable<Sheet: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Sheet
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented) {
            content()
                .frame(minWidth: 520, minHeight: 600)
        }
        #endif
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
