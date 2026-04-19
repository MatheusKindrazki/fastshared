import SwiftUI
import FastSharedCore

/// Settings — `design/screens.jsx` → `Settings()`.
///
/// Mono numbered section headers ("01 · sharing", "02 · backend", "03 · capture"),
/// 4-up retention pill picker, readonly metadata rows for the backend section,
/// amber-filled capture toggles, and a destructive "SIGN OUT DEVICE" button.
struct SettingsView: View {
    @Environment(\.subscriptionStore) private var subscriptionStore
    @Environment(\.paywallCoordinator) private var paywallCoordinator

    @State private var deviceIdSuffix: String = "------"
    @State private var confirmSignOut: Bool = false
    @State private var defaultRetention: RetentionPolicy = RetentionPolicy.default
    @State private var screenshotBannerOn: Bool = true
    @State private var actionButtonOn: Bool = true
    @State private var backTapOn: Bool = false
    @State private var cloudSyncOn: Bool = true
    @State private var snapshot: SubscriptionSnapshot = .free
    @State private var usageCount: Int = 0

    private let appGroupDefaults = UserDefaults(suiteName: AppGroupPaths.groupIdentifier)
    private let retentionKey = "default_retention_policy"
    private let cloudSyncKey = "cloud_sync_enabled_v1"

    var body: some View {
        ZStack {
            BrandPalette.ground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    crumb
                        .padding(.top, 16)

                    Text("Settings")
                        .font(.system(size: 44, weight: .bold))
                        .tracking(-1.8)
                        .foregroundStyle(BrandPalette.text)
                        .padding(.top, 18)

                    sharingSection
                        .padding(.top, 28)

                    usageSection
                        .padding(.top, 24)

                    proSection
                        .padding(.top, 24)

                    backendSection
                        .padding(.top, 24)

                    captureSection
                        .padding(.top, 24)

                    signOutButton
                        .padding(.top, 28)

                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(BrandPalette.text)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
    }

    // MARK: - Chrome

    private var crumb: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
            Text("MANIFEST")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.6)
        }
        .foregroundStyle(BrandPalette.textDim)
    }

    // MARK: - Sections

    private var sharingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Mono("01 · sharing", color: BrandPalette.amberAccent.hot)

            VStack(alignment: .leading, spacing: 6) {
                Text("Default retention")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BrandPalette.text)
                Text("applies in share sheet and screenshot banner")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(BrandPalette.textFaint)

                retentionPicker
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BrandPalette.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(BrandPalette.line, lineWidth: 1)
                    )
            )
        }
    }

    private var retentionPicker: some View {
        GatedRetentionPicker(
            selection: Binding(
                get: { defaultRetention },
                set: { policy in
                    defaultRetention = policy
                    appGroupDefaults?.set(policy.rawValue, forKey: retentionKey)
                }
            ),
            tier: currentTier,
            onPaywall: { trigger in
                paywallCoordinator.present(trigger)
            }
        )
    }

    private var currentTier: Tier {
        snapshot.isPro ? .pro(snapshot.tier ?? .monthly) : .free
    }

    // MARK: - Usage (Part 6 — B6.2)

    /// "Uploads today" row. For Free tier renders `"2 / 3"`; for Pro renders
    /// `"47 / ∞"` via the SF Symbol so Dynamic Type + RTL both render correctly.
    /// Reset time uses local midnight even though the counter is UTC-keyed —
    /// the UI value is a human convenience; the counter is tz-safe.
    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Mono("01.5 · usage", color: BrandPalette.amberAccent.hot)

            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                VStack(spacing: 0) {
                    usageRow(now: timeline.date)
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(BrandPalette.paper)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(BrandPalette.line, lineWidth: 1)
                        )
                )
            }
        }
    }

    @ViewBuilder
    private func usageRow(now: Date) -> some View {
        let formatter = DateFormatter()
        let _ = formatter.dateFormat = "h:mm a"
        let midnight = Calendar.current.nextDate(after: now,
                                                 matching: DateComponents(hour: 0, minute: 0),
                                                 matchingPolicy: .strict)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Uploads today")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BrandPalette.text)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(usageCount)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(BrandPalette.text)
                    Text("/")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(BrandPalette.textFaint)
                    if let cap = snapshot.caps.dailyUploadLimit {
                        Text("\(cap)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(BrandPalette.textDim)
                    } else {
                        Image(systemName: "infinity")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(BrandPalette.amberAccent.hot)
                            .accessibilityLabel("unlimited")
                    }
                }
            }
            if let midnight {
                Text("Resets at \(midnight.formatted(.dateTime.hour().minute()))")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(BrandPalette.textFaint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Pro section (B3.3)

    private var proSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Mono("01.7 · pro", color: BrandPalette.amberAccent.hot)

            VStack(spacing: 0) {
                cloudSyncRow
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BrandPalette.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(BrandPalette.line, lineWidth: 1)
                    )
            )
        }
    }

    private var cloudSyncRow: some View {
        let isPro = snapshot.isPro && snapshot.caps.allowsCloudSync
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Sync across devices")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BrandPalette.text)
                    if !isPro {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(BrandPalette.textDim)
                    }
                }
                Text(isPro
                     ? "Mirrors link history to your private iCloud."
                     : "Pro-only. Mirrors link history to your private iCloud.")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(BrandPalette.textFaint)
            }
            Spacer()
            AmberToggle(isOn: Binding(
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
            // WHY: disabled SwiftUI controls don't accept hit tests; a full-row
            // transparent button catches taps so Free users land in the paywall
            // instead of silently bouncing off the locked toggle.
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

    private func loadCloudSync() {
        // Default ON for Pro; only respect the stored value if explicitly set.
        if let stored = appGroupDefaults?.object(forKey: cloudSyncKey) as? Bool {
            cloudSyncOn = stored
        } else {
            cloudSyncOn = true
        }
    }

    private var backendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Mono("02 · backend", color: BrandPalette.amberAccent.hot)

            let rows: [(String, String)] = [
                ("API", AppGroupConfig.apiBaseURL.host ?? AppGroupConfig.apiBaseURL.absoluteString),
                ("SHORT", AppGroupConfig.shortLinkHost.host ?? AppGroupConfig.shortLinkHost.absoluteString),
                ("DEVICE", "\(platformTag) · ••••\(deviceIdSuffix)"),
                ("VERSION", appVersion),
            ]

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    HStack {
                        Mono(row.0, size: 10, color: BrandPalette.textFaint)
                            .frame(width: 80, alignment: .leading)
                        Text(row.1)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(BrandPalette.text)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .overlay(alignment: .bottom) {
                        if idx < rows.count - 1 {
                            Rectangle().fill(BrandPalette.line).frame(height: 1)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BrandPalette.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(BrandPalette.line, lineWidth: 1)
                    )
            )
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Mono("03 · capture", color: BrandPalette.amberAccent.hot)

            VStack(spacing: 0) {
                toggleRow(title: "Screenshot banner", on: $screenshotBannerOn, showDivider: true)
                toggleRow(title: "Action Button",     on: $actionButtonOn,      showDivider: true)
                toggleRow(title: "Back Tap (double)", on: $backTapOn,           showDivider: false)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BrandPalette.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(BrandPalette.line, lineWidth: 1)
                    )
            )
        }
    }

    private func toggleRow(title: String, on: Binding<Bool>, showDivider: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(BrandPalette.text)
            Spacer()
            AmberToggle(isOn: on)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if showDivider {
                Rectangle().fill(BrandPalette.line).frame(height: 1)
            }
        }
    }

    private var signOutButton: some View {
        let accent = BrandPalette.amberAccent
        return Button {
            confirmSignOut = true
        } label: {
            Text("SIGN OUT DEVICE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(accent.fade)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(accent.fade.opacity(0.27), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - State

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
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
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

    private func signOut() async {
        let keychain = KeychainStore(service: AppGroupConfig.identifier, accessGroup: AppGroupConfig.keychainAccessGroup)
        let tokenStore = DeviceTokenStore(keychain: keychain)
        try? await tokenStore.clear()
        deviceIdSuffix = "------"
    }
}

// MARK: - Supporting atoms

/// Amber-filled toggle matching the redesign's pill style.
private struct AmberToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        let accent = BrandPalette.amberAccent
        Button {
            withAnimation(.spring(duration: 0.28, bounce: 0.2)) {
                isOn.toggle()
            }
        } label: {
            ZStack {
                Capsule()
                    .fill(isOn ? accent.hot : BrandPalette.line)
                    .frame(width: 42, height: 25)
                HStack {
                    if isOn { Spacer() }
                    Circle()
                        .fill(Color.white)
                        .frame(width: 21, height: 21)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    if !isOn { Spacer() }
                }
                .frame(width: 42, height: 25)
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - RetentionPolicy shortLabel for the 4-up picker

private extension RetentionPolicy {
    /// Compact mono label used in the 4-up retention picker (1h / 24h / 1w / 1mo).
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
