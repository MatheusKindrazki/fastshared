import SwiftUI
import FastSharedCore

/// Settings — pixel-perfect redesign.
///
/// Sections: Sharing defaults · Quick share · This device · Danger zone.
/// Each section uses a card (bg paper, border 1px line, cornerRadius 20).
/// Rows have 14×16 padding; non-last rows have a 0.5pt bottom divider.
struct SettingsView: View {
    @Environment(\.subscriptionStore) private var subscriptionStore
    @Environment(\.paywallCoordinator) private var paywallCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @State private var deviceIdSuffix: String = "------"
    @State private var confirmSignOut: Bool = false
    @State private var confirmAppleSignOut: Bool = false
    @State private var showSignInSheet: Bool = false
    @State private var authRefreshToken: Int = 0
    @State private var defaultRetention: RetentionPolicy = RetentionPolicy.default
    @State private var screenshotBannerOn: Bool = true
    @State private var actionButtonOn: Bool = true
    @State private var backTapOn: Bool = false
    @State private var cloudSyncOn: Bool = true
    @State private var snapshot: SubscriptionSnapshot = .free
    @State private var usageCount: Int = 0
    @State private var copyLinkAuto: Bool = true
    @State private var notifyOnOpen: Bool = false
    #if DEBUG
    @State private var devUnlimitedCaps: Bool = DevOverrides.unlimitedFreeCaps
    #endif

    private let appGroupDefaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
    private let retentionKey = "default_retention_policy"
    private let cloudSyncKey = "cloud_sync_enabled_v1"

    // MARK: - Theme helpers — HIG semantic; adapts to light/dark.

    private var ground: Color { Color.sysGroupedBackground }
    private var paper: Color { Color.sysSecondaryGroupedBackground }
    private var textPrimary: Color { Color.sysLabel }
    private var textDim: Color { Color.sysSecondaryLabel }
    private var textFaint: Color { Color.sysTertiaryLabel }
    private var line: Color { Color.sysSeparator }

    // MARK: - Body

    var body: some View {
        ZStack {
            ground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Title block
                Text("Settings")
                    .font(.system(size: 28, weight: .bold))
                    .kerning(-0.025 * 28)
                    .foregroundStyle(textPrimary)
                    .padding(.top, 8)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        // 0. Account — Sign in with Apple upgrade path
                        accountSection
                            .id(authRefreshToken) // rebuild after sign-out

                        // 1. Sharing defaults
                        SettingsSection(
                            header: "Sharing defaults",
                            textDim: textDim,
                            paper: paper,
                            line: line
                        ) {
                            SettingsRow(
                                label: "Default expiration",
                                value: defaultRetention.displayName,
                                isDestructive: false,
                                hasChevron: true,
                                textPrimary: textPrimary,
                                textDim: textDim,
                                textFaint: textFaint,
                                line: line,
                                showDivider: true,
                                action: nil
                            )
                            SettingsRow(
                                label: "Copy link automatically",
                                value: copyLinkAuto ? "On" : "Off",
                                isDestructive: false,
                                hasChevron: true,
                                textPrimary: textPrimary,
                                textDim: textDim,
                                textFaint: textFaint,
                                line: line,
                                showDivider: true,
                                action: nil
                            )
                            SettingsRow(
                                label: "Notify me on open",
                                value: notifyOnOpen ? "On" : "Off",
                                isDestructive: false,
                                hasChevron: true,
                                textPrimary: textPrimary,
                                textDim: textDim,
                                textFaint: textFaint,
                                line: line,
                                showDivider: false,
                                action: nil
                            )
                        }

                        // 2. Quick share
                        SettingsSection(
                            header: "Quick share",
                            textDim: textDim,
                            paper: paper,
                            line: line
                        ) {
                            SettingsRow(
                                label: "Share sheet",
                                value: "Enabled",
                                isDestructive: false,
                                hasChevron: true,
                                textPrimary: textPrimary,
                                textDim: textDim,
                                textFaint: textFaint,
                                line: line,
                                showDivider: true,
                                action: nil
                            )
                            SettingsRow(
                                label: "Screenshot shortcut",
                                value: screenshotBannerOn ? "On" : "Off",
                                isDestructive: false,
                                hasChevron: true,
                                textPrimary: textPrimary,
                                textDim: textDim,
                                textFaint: textFaint,
                                line: line,
                                showDivider: true,
                                action: nil
                            )
                            SettingsRow(
                                label: "Action button",
                                value: actionButtonOn ? "FastShared" : "Off",
                                isDestructive: false,
                                hasChevron: true,
                                textPrimary: textPrimary,
                                textDim: textDim,
                                textFaint: textFaint,
                                line: line,
                                showDivider: false,
                                action: nil
                            )
                        }

                        // 3. This device
                        SettingsSection(
                            header: "This device",
                            textDim: textDim,
                            paper: paper,
                            line: line
                        ) {
                            SettingsRow(
                                label: "Device name",
                                value: "\(platformTag) ·  ••••\(deviceIdSuffix)",
                                isDestructive: false,
                                hasChevron: true,
                                textPrimary: textPrimary,
                                textDim: textDim,
                                textFaint: textFaint,
                                line: line,
                                showDivider: true,
                                action: nil
                            )
                            SettingsRow(
                                label: "Server",
                                value: AppGroupConfig.shortLinkHost.host ?? "fastsha.red",
                                isDestructive: false,
                                hasChevron: true,
                                textPrimary: textPrimary,
                                textDim: textDim,
                                textFaint: textFaint,
                                line: line,
                                showDivider: false,
                                action: nil
                            )
                        }

                        // 4. Danger zone
                        SettingsSection(
                            header: "Danger zone",
                            textDim: textDim,
                            paper: paper,
                            line: line
                        ) {
                            SettingsRow(
                                label: "Stop all active shares",
                                value: nil,
                                isDestructive: true,
                                hasChevron: true,
                                textPrimary: textPrimary,
                                textDim: textDim,
                                textFaint: textFaint,
                                line: line,
                                showDivider: true,
                                action: nil
                            )
                            SettingsRow(
                                label: "Reset this device",
                                value: nil,
                                isDestructive: true,
                                hasChevron: true,
                                textPrimary: textPrimary,
                                textDim: textDim,
                                textFaint: textFaint,
                                line: line,
                                showDivider: false,
                                action: { confirmSignOut = true }
                            )
                        }

                        // Pro / Sync row (preserved from original)
                        proSyncSection

                        // Usage section (preserved from original)
                        usageSectionView

                        #if DEBUG
                        // Developer — DEBUG builds only. Toggles the dev bypass
                        // for free-tier caps (daily count, file size, retention).
                        SettingsSection(
                            header: "Developer",
                            textDim: textDim,
                            paper: paper,
                            line: line
                        ) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Unlimited free uploads")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(textPrimary)
                                    Text("DEBUG: skip all free-tier gates so you can test every flow.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(textDim)
                                }
                                Spacer()
                                Toggle("", isOn: $devUnlimitedCaps)
                                    .labelsHidden()
                                    .tint(BrandPalette.accent.hot)
                                    .onChange(of: devUnlimitedCaps) { _, new in
                                        DevOverrides.setUnlimitedFreeCaps(new)
                                    }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        #endif

                        // Footer
                        Text("FastShared · \(appVersion)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(textFaint)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 10)
                            .padding(.bottom, 20)
                    }
                    .padding(.top, 4)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }
        }
        .foregroundStyle(textPrimary)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .task {
            await loadDeviceId()
            loadDefaultRetention()
            loadCloudSync()
            snapshot = await subscriptionStore.currentSnapshot()
            for await next in subscriptionStore.snapshotStream {
                snapshot = next
            }
        }
        .task {
            usageCount = await UsageTracker.shared.currentCount()
        }
        .confirmationDialog("Sign out this device?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task { await signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will lose access to history on this device until you sign in again.")
        }
        .confirmationDialog("Sign out of FastShared?", isPresented: $confirmAppleSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task { await appleSignOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Apple account will be disconnected on this device. Your shares stay where they are.")
        }
        .sheet(isPresented: $showSignInSheet) {
            SignInView(onComplete: {
                showSignInSheet = false
                authRefreshToken &+= 1 // force section rebuild with fresh AuthState
            })
        }
    }

    // MARK: - Account section

    /// The auth-mode reading is wrapped in a computed property so it reruns
    /// after `authRefreshToken` flips (SwiftUI re-reads body). `AuthState`
    /// is UserDefaults-backed and not Observable, so we force invalidation
    /// via the `.id(authRefreshToken)` modifier on the section view.
    private var accountMode: AuthState.Mode? {
        _ = authRefreshToken
        return AuthState.currentMode
    }

    @ViewBuilder
    private var accountSection: some View {
        let mode = accountMode
        SettingsSection(
            header: "Account",
            textDim: textDim,
            paper: paper,
            line: line
        ) {
            switch mode {
            case .apple:
                appleAccountRows
            case .guest, .none:
                guestAccountRows
            }
        }
    }

    @ViewBuilder
    private var guestAccountRows: some View {
        // Row 1 — status
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Not signed in")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(textPrimary)
                Text("Sync off — your shares live only on this device.")
                    .font(.system(size: 12))
                    .foregroundStyle(textDim)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)

        Rectangle()
            .fill(line)
            .frame(height: 0.5)
            .padding(.leading, 16)

        // Row 2 — Sign in (accent)
        Button {
            showSignInSheet = true
        } label: {
            HStack {
                Text("Sign in with Apple")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BrandPalette.accentHot)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(textFaint)
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var appleAccountRows: some View {
        // Row 1 — header + name/email
        let identityLabel: String = authFullName ?? authEmail ?? "Apple account"
        VStack(alignment: .leading, spacing: 4) {
            Text("SIGNED IN AS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(textFaint)
            Text(identityLabel)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)

        Rectangle()
            .fill(line)
            .frame(height: 0.5)
            .padding(.leading, 16)

        // Row 2 — Apple ID truncated prefix
        HStack {
            Text("Apple ID")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(textPrimary)
            Spacer()
            Text(truncatedAppleUserId)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(textDim)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)

        Rectangle()
            .fill(line)
            .frame(height: 0.5)
            .padding(.leading, 16)

        // Row 3 — Sign out (destructive)
        Button {
            confirmAppleSignOut = true
        } label: {
            HStack {
                Text("Sign out")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(BrandPalette.urgencyCritical)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(textFaint)
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Auth read helpers
    //
    // NOTE: If the parallel agent has exposed `AuthState.fullName`,
    // `AuthState.email`, and `AuthState.appleUserId` as public static
    // getters, prefer those. Until then — or as a safe fallback if those
    // accessors aren't present — we read the same UserDefaults keys that
    // `AuthState.markSignedInOrGuest` writes.
    private var authDefaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
    }
    private var authFullName: String? {
        authDefaults?.string(forKey: AuthState.appleNameKey)
    }
    private var authEmail: String? {
        authDefaults?.string(forKey: AuthState.appleEmailKey)
    }
    private var authAppleUserId: String? {
        authDefaults?.string(forKey: AuthState.appleUserIdKey)
    }
    private var truncatedAppleUserId: String {
        guard let id = authAppleUserId, !id.isEmpty else { return "—" }
        if id.count <= 10 { return id }
        return String(id.prefix(10)) + "…"
    }

    /// Apple-sign-out handler. Flips AuthState back to nil (so the gate can
    /// re-prompt on next launch if the app decides to), clears the device
    /// token so the account is fully disconnected on this device, and bumps
    /// the refresh token so the UI rebuilds the Account section in-place.
    ///
    /// TODO: once `tokenStore` is available via an `@Environment` value, use
    /// the injected instance instead of instantiating `DeviceTokenStore`
    /// locally here.
    private func appleSignOut() async {
        AuthState.reset()
        let keychain = KeychainStore(service: AppGroupConfig.identifier, accessGroup: AppGroupConfig.keychainAccessGroup)
        let tokenStore = DeviceTokenStore(keychain: keychain)
        try? await tokenStore.clear()
        await MainActor.run {
            authRefreshToken &+= 1
            deviceIdSuffix = "------"
        }
    }

    // MARK: - Pro sync section (preserved)

    private var proSyncSection: some View {
        SettingsSection(
            header: "Pro · Sync",
            textDim: textDim,
            paper: paper,
            line: line
        ) {
            let isPro = snapshot.isPro && snapshot.caps.allowsCloudSync
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Sync across devices")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(textPrimary)
                        if !isPro {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(textDim)
                        }
                    }
                    Text(isPro
                         ? "Mirrors link history to your private iCloud."
                         : "Pro only. Mirrors link history to your iCloud.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(textFaint)
                }
                Spacer()
                FriendlyToggle(isOn: Binding(
                    get: { cloudSyncOn && isPro },
                    set: { newValue in
                        if isPro {
                            cloudSyncOn = newValue
                            appGroupDefaults?.set(newValue, forKey: cloudSyncKey)
                        }
                    }
                ))
                .disabled(!isPro)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay {
                if !isPro {
                    Button {
                        paywallCoordinator.present(.cloudSyncRequested)
                    } label: {
                        Color.clear
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sync across devices — Pro only")
                    .accessibilityHint("Opens the Pro upgrade screen")
                }
            }
        }
    }

    // MARK: - Usage section (preserved)

    private var usageSectionView: some View {
        SettingsSection(
            header: "Usage",
            textDim: textDim,
            paper: paper,
            line: line
        ) {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                usageRowContent(now: timeline.date)
            }
        }
    }

    @ViewBuilder
    private func usageRowContent(now: Date) -> some View {
        let midnight = Calendar.current.nextDate(after: now,
                                                 matching: DateComponents(hour: 0, minute: 0),
                                                 matchingPolicy: .strict)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Uploads today")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(usageCount)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(textPrimary)
                    Text("/")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(textFaint)
                    if let cap = snapshot.caps.dailyUploadLimit {
                        Text("\(cap)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(textDim)
                    } else {
                        Image(systemName: "infinity")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(BrandPalette.accentHot)
                            .accessibilityLabel("unlimited")
                    }
                }
            }
            if let midnight {
                Text("Resets at \(midnight.formatted(.dateTime.hour().minute()))")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(textFaint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - State helpers

    private var platformTag: String {
        #if os(iOS)
        return "ios"
        #elseif os(macOS)
        return "macos"
        #else
        return "unknown"
        #endif
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func loadDeviceId() async {
        let keychain = KeychainStore(service: AppGroupConfig.identifier, accessGroup: AppGroupConfig.keychainAccessGroup)
        let tokenStore = DeviceTokenStore(keychain: keychain)
        if let token = try? await tokenStore.load() {
            let full = token.deviceId.uuidString
            deviceIdSuffix = String(full.suffix(6))
        }
    }

    private func loadDefaultRetention() {
        if let raw = appGroupDefaults?.string(forKey: retentionKey),
           let policy = RetentionPolicy(rawValue: raw) {
            defaultRetention = policy
        } else {
            defaultRetention = .default
        }
    }

    private func loadCloudSync() {
        if let stored = appGroupDefaults?.object(forKey: cloudSyncKey) as? Bool {
            cloudSyncOn = stored
        } else {
            cloudSyncOn = true
        }
    }

    private func signOut() async {
        let keychain = KeychainStore(service: AppGroupConfig.identifier, accessGroup: AppGroupConfig.keychainAccessGroup)
        let tokenStore = DeviceTokenStore(keychain: keychain)
        try? await tokenStore.clear()
        deviceIdSuffix = "------"
    }
}

// MARK: - SettingsSection

private struct SettingsSection<Content: View>: View {
    let header: String
    let textDim: Color
    let paper: Color
    let line: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(textDim)
                .padding(.leading, 6)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(line, lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

// MARK: - SettingsRow

private struct SettingsRow: View {
    let label: String
    let value: String?
    let isDestructive: Bool
    let hasChevron: Bool
    let textPrimary: Color
    let textDim: Color
    let textFaint: Color
    let line: Color
    let showDivider: Bool
    let action: (() -> Void)?

    var body: some View {
        let labelColor = isDestructive ? BrandPalette.urgencyCritical : textPrimary
        VStack(spacing: 0) {
            Group {
                if let action {
                    Button(action: action) {
                        rowContent(labelColor: labelColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    rowContent(labelColor: labelColor)
                }
            }

            if showDivider {
                Rectangle()
                    .fill(line)
                    .frame(height: 0.5)
                    .padding(.leading, 16)
            }
        }
    }

    private func rowContent(labelColor: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(labelColor)
            Spacer()
            if let value {
                Text(value)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(textDim)
                    .lineLimit(1)
            }
            if hasChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(textFaint)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - FriendlyToggle (violet accent, replaces AmberToggle for redesign)

private struct FriendlyToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.28, bounce: 0.2)) {
                isOn.toggle()
            }
        } label: {
            ZStack {
                Capsule()
                    .fill(isOn ? BrandPalette.accentHot : Color.sysSeparator)
                    .frame(width: 42, height: 25)
                HStack {
                    if isOn { Spacer() }
                    Circle()
                        .fill(Color.white)
                        .frame(width: 21, height: 21)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    if !isOn { Spacer() }
                }
                .frame(width: 42, height: 25)
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - RetentionPolicy shortLabel

private extension RetentionPolicy {
    var shortLabel: String {
        switch self {
        case .oneHour: return "1h"
        case .oneDay: return "24h"
        case .oneWeek: return "1w"
        case .oneMonth: return "1mo"
        default: return displayName
        }
    }
}
