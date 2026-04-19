import SwiftUI
import FastSharedCore

#if canImport(UIKit)
import UIKit
#endif

/// Single-page declarative onboarding, per `design/screens.jsx` → `Onboarding()`.
///
/// The layout: a blurred amber sphere in the top-right backdrop, a heavy
/// display headline split across four lines, a body paragraph, a three-step
/// mono ledger ("01 SHARE / 02 PICK / 03 PASTE"), and an amber CTA block.
struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(\.apiClient) private var apiClient
    @State private var isProvisioning: Bool = false
    @State private var errorMessage: String?
    @State private var startedPulse: Int = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            // WHY: the brand ground is near-black, which on a device with
            // physical dark bezels (iPhone 17 Pro Max notch + home indicator
            // area) makes the top and bottom of the screen read as letterbox
            // rather than as a full-bleed canvas. Two soft radial washes
            // push life into those edges — amber glow from the sphere's
            // origin at the top-right, violet ambient from bottom-left —
            // while the base ground still anchors the overall darkness.
            BrandPalette.ground
                .ignoresSafeArea()

            RadialGradient(
                colors: [BrandPalette.amberAccent.hot.opacity(0.22), .clear],
                center: .init(x: 0.9, y: 0.08),
                startRadius: 0,
                endRadius: 620
            )
            .ignoresSafeArea()
            .blendMode(.screen)
            .allowsHitTesting(false)

            RadialGradient(
                colors: [Color(red: 0.23, green: 0.11, blue: 0.40).opacity(0.55), .clear],
                center: .init(x: 0.1, y: 0.95),
                startRadius: 0,
                endRadius: 700
            )
            .ignoresSafeArea()
            .blendMode(.screen)
            .allowsHitTesting(false)

            // Ambient plane-arc — framed hero moment bleeding into the top-right
            // corner, per v3 `Onboarding()` (design/screens.jsx). The mark itself
            // ships with its own ambient glow; we add a little extra blur + opacity
            // so it reads as decorative backdrop rather than hero focus.
            PlaneArcMark(size: 160, framed: true, ambient: true)
                .opacity(0.5)
                .blur(radius: 12)
                .offset(x: 180, y: -40)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            GeometryReader { geo in
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 28)
                        .padding(.top, 40)

                    Spacer(minLength: 0)

                    ledger
                        .padding(.horizontal, 28)

                    Spacer(minLength: 16)

                    cta
                        .padding(.horizontal, 22)
                        .padding(.bottom, max(32, geo.safeAreaInsets.bottom))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(BrandPalette.text)
        #if os(iOS)
        .sensoryFeedback(.success, trigger: startedPulse)
        #endif
    }

    // MARK: - Sections

    private var header: some View {
        let accent = BrandPalette.amberAccent
        return VStack(alignment: .leading, spacing: 22) {
            Mono("fastshared · v1", color: accent.hot)

            // Display headline — 58pt / -0.045em tracking / 0.92 line height.
            (
                Text("Share\nanything.\n")
                    .foregroundStyle(BrandPalette.text)
                + Text("Vanishes\n")
                    .foregroundStyle(accent.hot)
                + Text("on schedule.")
                    .foregroundStyle(BrandPalette.text)
            )
            .font(.system(size: 58, weight: .bold))
            .tracking(-2.6)
            .lineSpacing(-6)
            .fixedSize(horizontal: false, vertical: true)

            Text("From the share sheet, Action Button, or drag onto the dock — FastShared uploads in the background, copies a temporary link, and deletes the file when time's up.")
                .font(.system(size: 16, weight: .regular))
                .lineSpacing(4)
                .foregroundStyle(BrandPalette.textDim)
                .frame(maxWidth: 320, alignment: .leading)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(BrandPalette.amberAccent.fade)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ledger: some View {
        let accent = BrandPalette.amberAccent
        let steps: [(String, String, String)] = [
            ("01", "SHARE", "any file, anywhere"),
            ("02", "PICK", "1h · 24h · 1w · 1mo"),
            ("03", "PASTE", "link lands in clipboard"),
        ]
        return VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                HStack(spacing: 14) {
                    // Big amber numeral
                    Text(step.0)
                        .font(.system(size: 28, weight: .medium, design: .monospaced))
                        .tracking(-1.0)
                        .foregroundStyle(accent.hot)
                        .frame(width: 52, alignment: .leading)

                    // Headline + sub
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.1)
                            .font(.system(size: 15, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(BrandPalette.text)
                        Text(step.2)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(BrandPalette.textFaint)
                    }

                    Spacer(minLength: 0)

                    // Amber progress tick (fades with index).
                    Rectangle()
                        .fill(accent.hot)
                        .frame(width: 32, height: 2)
                        .opacity(0.2 + Double(idx) * 0.3)
                }
                .padding(.vertical, 14)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(idx == 0 ? BrandPalette.lineStrong : BrandPalette.line)
                        .frame(height: 1)
                }
            }
        }
    }

    private var cta: some View {
        let accent = BrandPalette.amberAccent
        return VStack(spacing: 14) {
            Button {
                Task { await provision() }
            } label: {
                HStack {
                    if isProvisioning {
                        ProgressView().tint(Color(red: 0.07, green: 0.02, blue: 0.04))
                    }
                    Text(isProvisioning ? "PROVISIONING" : "GET STARTED")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(1.8)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.07, green: 0.02, blue: 0.04))
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(accent.hot, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isProvisioning)
            #if os(iOS)
            .keyboardShortcut(.defaultAction)
            #endif

            Mono("no account · no sign-in · no trace",
                 size: 10, track: 1.4, color: BrandPalette.textFaint)
        }
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

#Preview {
    OnboardingView(onComplete: {})
}
