import SwiftUI
import FastSharedCore

#if canImport(UIKit)
import UIKit
#endif

/// Full-bleed onboarding. Three pages, each deserving the whole canvas, no system page dots.
/// A thin amber→coral progress rail at the top is the only navigation affordance besides the buttons.
struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(\.apiClient) private var apiClient
    @State private var page: Int = 0
    @State private var isProvisioning: Bool = false
    @State private var errorMessage: String?
    @State private var startedPulse: Int = 0

    private let totalPages: Int = 3

    var body: some View {
        ZStack {
            BrandPalette.canvas
                .ignoresSafeArea(.all)

            VStack(spacing: 0) {
                ProgressLine(fraction: Double(page + 1) / Double(totalPages))

                topBar
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                ZStack {
                    switch page {
                    case 0: WelcomePage().transition(pageTransition)
                    case 1: HowItWorksPage().transition(pageTransition)
                    default: EphemeralPage().transition(pageTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(duration: 0.55, bounce: 0.22), value: page)

                controls
            }
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(BrandPalette.milk)
        #if os(iOS)
        .sensoryFeedback(.success, trigger: startedPulse)
        #endif
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            if page > 0 {
                Button {
                    page = max(0, page - 1)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("BACK")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .tracking(1.6)
                    }
                    .foregroundStyle(BrandPalette.milk.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if page < totalPages - 1 {
                Button {
                    page = totalPages - 1
                } label: {
                    Text("SKIP")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(BrandPalette.milk.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 24)
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        )
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(BrandPalette.coral)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if page < totalPages - 1 {
                HStack {
                    Spacer()
                    Button {
                        page = min(page + 1, totalPages - 1)
                    } label: {
                        HStack(spacing: 8) {
                            Text("CONTINUE")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .tracking(1.8)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(BrandPalette.ink)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(BrandPalette.amber, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Button {
                    Task { await provision() }
                } label: {
                    HStack(spacing: 10) {
                        if isProvisioning {
                            ProgressView().tint(BrandPalette.ink)
                        }
                        Text(isProvisioning ? "PROVISIONING…" : "GET STARTED")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .tracking(1.8)
                    }
                    .foregroundStyle(BrandPalette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(BrandPalette.amber, in: Capsule())
                    .shadow(color: BrandPalette.amber.opacity(0.4), radius: 24, y: 4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(isProvisioning)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
        .padding(.top, 12)
    }

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

// MARK: - Page 1 · The idea

private struct WelcomePage: View {
    @State private var headlinesAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            ArcMark()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: -8) {
                    staggered("Share anything.", delay: 0.10, color: BrandPalette.milk)
                    staggered("Get a link.", delay: 0.22, color: BrandPalette.milk)
                    staggered("Watch it vanish.", delay: 0.34, color: BrandPalette.coral, italic: true)
                }
                Spacer(minLength: 32)
                Text("FASTSHARED · 2026")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(BrandPalette.milk.opacity(0.35))
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation(BrandMotion.transition.delay(0.25)) { headlinesAppeared = true }
        }
    }

    private func staggered(_ text: String, delay: Double, color: Color, italic: Bool = false) -> some View {
        let base = Text(text)
            .font(.system(size: 60, weight: .bold))
        let styled = italic ? base.italic() : base
        return styled
            .tracking(-2.4)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .opacity(headlinesAppeared || reduceMotion ? 1 : 0)
            .offset(y: headlinesAppeared || reduceMotion ? 0 : 14)
            .animation(BrandMotion.transition.delay(delay), value: headlinesAppeared)
    }
}

// MARK: - Page 2 · How it works

private struct HowItWorksPage: View {
    private struct Step: Identifiable {
        let id: Int
        let number: String
        let headline: String
        let caption: String
    }

    private let steps: [Step] = [
        Step(id: 1, number: "01", headline: "Share any file",
             caption: "image · video · document · whatever"),
        Step(id: 2, number: "02", headline: "Pick how long it lives",
             caption: "1 hour · 24 hours · 1 week · 1 month"),
        Step(id: 3, number: "03", headline: "Your link lands in the clipboard",
             caption: "paste it anywhere — it expires by itself")
    ]

    @State private var appeared: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            header
            VStack(alignment: .leading, spacing: 28) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                    StepBlock(step: step)
                        .opacity(appeared || reduceMotion ? 1 : 0)
                        .offset(y: appeared || reduceMotion ? 0 : 16)
                        .animation(BrandMotion.transition.delay(0.12 * Double(idx)), value: appeared)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .onAppear {
            withAnimation { appeared = true }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOW IT WORKS")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(BrandPalette.amber)
            Text("Three moves.")
                .font(.system(size: 44, weight: .bold))
                .tracking(-1.8)
                .foregroundStyle(BrandPalette.milk)
        }
    }

    private struct StepBlock: View {
        let step: Step

        var body: some View {
            HStack(alignment: .top, spacing: 20) {
                Text(step.number)
                    .font(.system(size: 64, weight: .bold))
                    .tracking(-2.4)
                    .foregroundStyle(BrandPalette.amber)
                    .frame(width: 90, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Text(step.headline)
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.6)
                        .foregroundStyle(BrandPalette.milk)
                    Text(step.caption)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(BrandPalette.milk.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Page 3 · The promise

private struct EphemeralPage: View {
    @State private var appeared: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            HourglassBead()
                .frame(height: 160)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                Text("Every link")
                    .font(.system(size: 48, weight: .bold))
                    .tracking(-2.0)
                + Text("\nexpires.")
                    .font(.system(size: 48, weight: .bold))
                    .tracking(-2.0)
                    .foregroundStyle(BrandPalette.amber)

                Text("Every file is deleted. By design.")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(BrandPalette.milk.opacity(0.7))
            }

            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .semibold))
                Text("DEFAULT · 24 HOURS")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
            }
            .foregroundStyle(BrandPalette.amber)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().stroke(BrandPalette.amber.opacity(0.4), lineWidth: 1)
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 14)
        .onAppear {
            withAnimation(BrandMotion.transition) { appeared = true }
        }
    }
}
