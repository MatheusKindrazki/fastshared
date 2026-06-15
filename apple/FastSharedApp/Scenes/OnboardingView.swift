import SwiftUI
import FastSharedCore

#if canImport(UIKit)
import UIKit
#endif

/// Single-page declarative onboarding — "Friendly" redesign v2.
///
/// Layout: warm off-white ground, centered hero mark + headline, three
/// step cards, and a large violet CTA footer that stays pinned at the
/// bottom of the safe area.
struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(\.apiClient) private var apiClient
    @Environment(\.colorScheme) private var colorScheme

    @State private var isProvisioning: Bool = false
    @State private var errorMessage: String?
    @State private var startedPulse: Int = 0

    // MARK: - Resolved tokens — HIG semantic; adapts to light/dark.

    private var groundColor: Color { Color.sysBackground }
    private var textColor: Color { Color.sysLabel }
    private var textDimColor: Color { Color.sysSecondaryLabel }
    private var textFaintColor: Color { Color.sysTertiaryLabel }
    private var cardBgColor: Color { Color.sysSecondaryBackground }
    private var lineColor: Color { Color.sysSeparator }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    heroBlock
                        .padding(.top, 28)
                        .padding(.bottom, 36)
                        .padding(.horizontal, 24)

                    stepsBlock
                        .padding(.horizontal, 24)

                    Spacer(minLength: 24)

                    Color.clear.frame(height: 1)
                }
                // Ensure the scroll content is always at least tall enough for
                // the footer to be pushed to the bottom.
                .frame(minHeight: geo.size.height - footerHeight(geo: geo), alignment: .top)
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)

            // Footer pinned over scroll content
            VStack {
                Spacer()
                footerBlock(geo: geo)
            }
        }
        .background(groundColor.ignoresSafeArea())
        .foregroundStyle(textColor)
        #if os(iOS)
        .sensoryFeedback(.success, trigger: startedPulse)
        #endif
    }

    // MARK: - Hero

    private var heroBlock: some View {
        VStack(spacing: 20) {
            PlaneArcMark(size: 88, ambient: true)
                .accessibilityHidden(true)

            Text("Share files that don't stick around.")
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.03 * 32)
                .lineSpacing(0.1 * 32)
                .multilineTextAlignment(.center)
                .foregroundStyle(textColor)
                .lineLimit(2)

            Text("Fast, temporary links. No accounts, no clutter.")
                .font(.system(size: 15))
                .foregroundStyle(textDimColor)
                .lineSpacing(1.5)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Step cards

    private let steps: [(emoji: String, title: String, body: String)] = [
        ("📤", "Share like you always do", "From Photos, Files, or anywhere with the share sheet."),
        ("🔗", "We create a link, you copy it", "Auto-copied. Paste in chat, email, anywhere."),
        ("✨", "It disappears on schedule", "Default: 24 hours. Change it any time, or stop it yourself."),
    ]

    private var stepsBlock: some View {
        VStack(spacing: 14) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                stepCard(emoji: step.emoji, title: step.title, body: step.body)
            }
        }
    }

    private func stepCard(emoji: String, title: String, body: String) -> some View {
        HStack(spacing: 14) {
            // Icon tile
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BrandPalette.accentHot.opacity(0.12))
                    .frame(width: 44, height: 44)
                Text(emoji)
                    .font(.system(size: 22))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(textColor)
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(textDimColor)
                    .lineSpacing(1.45)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(cardBgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(lineColor, lineWidth: 1)
                )
        )
    }

    // MARK: - Footer

    private func footerHeight(geo: GeometryProxy) -> CGFloat {
        // Approximate height: button ~52 + microcopy ~20 + margin top 14 + padding top 24 + bottom safe area
        return 52 + 20 + 14 + 24 + 30 + max(geo.safeAreaInsets.bottom, 0)
    }

    private func footerBlock(geo: GeometryProxy) -> some View {
        VStack(spacing: 14) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(BrandPalette.urgencyCritical)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                Task { await provision() }
            } label: {
                HStack {
                    if isProvisioning {
                        ProgressView()
                            .scaleEffect(0.85)
                    }
                    Text(isProvisioning ? "Setting up…" : "Get started")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isProvisioning)
            #if os(iOS)
            .keyboardShortcut(.defaultAction)
            #endif

            Text("No sign-up needed. Works offline-first.")
                .font(.system(size: 12))
                .foregroundStyle(textFaintColor)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
        .padding(.horizontal, 24)
        .padding(.bottom, max(30, geo.safeAreaInsets.bottom + 8))
        .background(
            // Gradient fade from transparent ground at top to opaque at bottom
            LinearGradient(
                stops: [
                    .init(color: groundColor.opacity(0), location: 0),
                    .init(color: groundColor, location: 0.35),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Provisioning

    private func provision() async {
        errorMessage = nil
        isProvisioning = true
        defer { isProvisioning = false }
        do {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            let token = try await apiClient.registerDevice(platform: currentPlatform, appVersion: version)
            let keychain = KeychainStore(service: AppGroupConfig.identifier, accessGroup: AppGroupConfig.keychainAccessGroup)
            let tokenStore = DeviceTokenStore(keychain: keychain)
            try await tokenStore.save(token)
            await PushNotificationRegistrar.syncCachedAPNSToken(apiClient: apiClient,
                                                                tokenStore: tokenStore)
            startedPulse &+= 1
            onComplete()
        } catch {
            errorMessage = "Could not register this device. \(error.localizedDescription)"
        }
    }

    private var currentPlatform: String {
        #if os(iOS)
        return "ios"
        #elseif os(macOS)
        return "macos"
        #else
        return "unknown"
        #endif
    }
}

#Preview("Light") {
    OnboardingView(onComplete: {})
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    OnboardingView(onComplete: {})
        .preferredColorScheme(.dark)
}
