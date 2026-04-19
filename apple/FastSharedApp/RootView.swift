import SwiftUI
import FastSharedCore

struct RootView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded: Bool = false

    var body: some View {
        Group {
            if hasOnboarded {
                content
            } else {
                OnboardingView(onComplete: { hasOnboarded = true })
            }
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
