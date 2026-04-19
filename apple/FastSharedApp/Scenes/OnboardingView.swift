import SwiftUI
import FastSharedCore

#if canImport(UIKit)
import UIKit
#endif

struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(\.apiClient) private var apiClient
    @State private var page: Int = 0
    @State private var isProvisioning: Bool = false
    @State private var errorMessage: String?

    private var totalPages: Int { 3 }

    var body: some View {
        ZStack {
            BrandPalette.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                content
                Divider()
                    .background(BrandPalette.milk.opacity(0.08))
                controls
            }
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(BrandPalette.milk)
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        TabView(selection: $page) {
            WelcomePage().tag(0)
            HowItWorksPage().tag(1)
            EphemeralPage().tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .animation(BrandMotion.transition, value: page)
        #else
        Group {
            switch page {
            case 0: WelcomePage()
            case 1: HowItWorksPage()
            default: EphemeralPage()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(BrandMotion.transition, value: page)
        #endif
    }

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
                nextRow
            } else {
                finalRow
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var nextRow: some View {
        HStack {
            #if os(macOS)
            Button {
                if page > 0 { page -= 1 }
            } label: {
                Text("Back")
                    .font(.body.weight(.medium))
                    .foregroundStyle(BrandPalette.milk.opacity(page > 0 ? 0.8 : 0.3))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .disabled(page == 0)
            Spacer()
            #endif

            Button {
                page = min(page + 1, totalPages - 1)
            } label: {
                HStack(spacing: 8) {
                    Text("Next")
                        .font(.body.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(BrandPalette.ink)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(BrandPalette.amber, in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var finalRow: some View {
        Button {
            Task { await provision() }
        } label: {
            HStack(spacing: 10) {
                if isProvisioning {
                    ProgressView()
                        .tint(BrandPalette.ink)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text(isProvisioning ? "Getting ready" : "Get started")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(BrandPalette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(BrandPalette.amber, in: Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .disabled(isProvisioning)
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

// MARK: - Pages

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            TemporalHero()
                .frame(height: 160)
            VStack(spacing: 10) {
                Text("Share anything.")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.8)
                Text("Get a link.")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(BrandPalette.amber)
            }
            Text("Photos, videos, files — turn them into a short link you can send anywhere. Every link is temporary by design.")
                .font(.body)
                .foregroundStyle(BrandPalette.milk.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

private struct HowItWorksPage: View {
    private struct Step: Identifiable {
        let id: Int
        let number: String
        let icon: String
        let title: String
        let detail: String
    }

    private let steps: [Step] = [
        Step(id: 1, number: "01", icon: "square.and.arrow.up",
             title: "Share anything",
             detail: "Pick a photo, video, or file from any app."),
        Step(id: 2, number: "02", icon: "timer",
             title: "Pick how long",
             detail: "1 hour, 1 day, 1 week, or 1 month."),
        Step(id: 3, number: "03", icon: "link",
             title: "Send the link",
             detail: "It lands in your clipboard. Send it, and forget about it.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 4) {
                Text("How it works")
                    .font(.caption.weight(.medium))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(BrandPalette.ember)
                Text("Three steps.")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.7)
            }
            VStack(spacing: 10) {
                ForEach(steps) { step in
                    StepCard(step: step)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private struct StepCard: View {
        let step: Step

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                Text(step.number)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(-0.5)
                    .foregroundStyle(BrandPalette.amber)
                    .frame(width: 50, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: step.icon)
                            .font(.headline)
                            .foregroundStyle(BrandPalette.ember)
                        Text(step.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(BrandPalette.milk)
                    }
                    Text(step.detail)
                        .font(.subheadline)
                        .foregroundStyle(BrandPalette.milk.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BrandPalette.violet.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(BrandPalette.amber.opacity(0.14), lineWidth: 1)
            )
        }
    }
}

private struct EphemeralPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(BrandPalette.amber.opacity(0.14))
                    .frame(width: 180, height: 180)
                    .blur(radius: 30)
                Image(systemName: "hourglass.bottomhalf.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(BrandPalette.arc)
            }
            VStack(spacing: 10) {
                Text("Your links are temporary.")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.6)
                    .multilineTextAlignment(.center)
                Text("Every link expires. Every file is deleted. By design.")
                    .font(.body)
                    .foregroundStyle(BrandPalette.milk.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Label("Default: 24 hours", systemImage: "timer")
                .font(.footnote.weight(.medium))
                .foregroundStyle(BrandPalette.amber)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(BrandPalette.violet.opacity(0.6), in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Hero illustration

/// Amber origin sphere → arc → fading particles. The brand mark in motion, rebuilt with SF Symbols + shapes so it
/// stays crisp at any scale and honours Reduce Motion.
private struct TemporalHero: View {
    @State private var drift: CGFloat = 0
    @State private var pulse: Bool = false

    private var reduceMotion: Bool {
        #if canImport(UIKit)
        return UIAccessibility.isReduceMotionEnabled
        #else
        return false
        #endif
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cy = h / 2
            ZStack {
                // Glow
                Circle()
                    .fill(BrandPalette.amber.opacity(pulse && !reduceMotion ? 0.35 : 0.2))
                    .frame(width: 150, height: 150)
                    .blur(radius: 24)
                    .position(x: w * 0.22, y: cy)

                // Origin sphere
                Circle()
                    .fill(RadialGradient(colors: [BrandPalette.ember, BrandPalette.amber],
                                         center: .center,
                                         startRadius: 0,
                                         endRadius: 40))
                    .frame(width: 64, height: 64)
                    .shadow(color: BrandPalette.amber.opacity(0.6), radius: 12)
                    .position(x: w * 0.22, y: cy)

                // Arc trailing off
                ArcShape()
                    .stroke(BrandPalette.arc, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .opacity(0.85)

                // Paperplane riding the fade
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(BrandPalette.coral)
                    .rotationEffect(.degrees(-18))
                    .position(x: w * (0.6 + (reduceMotion ? 0 : drift * 0.04)),
                              y: cy - 18 + (reduceMotion ? 0 : drift * 2))

                // Particle trail
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { i in
                        Circle()
                            .fill(BrandPalette.dust)
                            .frame(width: CGFloat(6 - i), height: CGFloat(6 - i))
                            .opacity(Double(5 - i) / 6.0)
                    }
                }
                .position(x: w * 0.82, y: cy + 4)

                // Trailing "sparkles" SF Symbol echoing the brand mark's ghost node
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(BrandPalette.dust.opacity(0.7))
                    .position(x: w * 0.92, y: cy - 14)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulse = true
                drift = 1
            }
        }
        .accessibilityLabel("FastShared launches a temporary link")
    }
}

private struct ArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.width * 0.30, y: rect.height * 0.55)
        let end = CGPoint(x: rect.width * 0.78, y: rect.height * 0.40)
        let control = CGPoint(x: rect.width * 0.50, y: rect.height * 0.10)
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}
