#if os(iOS)
import SwiftUI
import UIKit
import FastSharedCore

/// Soft nudge that slides in from the top of the hub when the user takes a
/// screenshot. 10s auto-dismiss. Tap "Share it →" to feed it into the pipeline;
/// tap Dismiss to hide. Layout matches the Friendly redesign spec.
@MainActor
struct ScreenshotBanner: View {
    let pending: PendingScreenshot
    let onUpload: () -> Void
    let onDismiss: () -> Void

    @State private var drainProgress: Double = 1.0
    @State private var uploadTick: Int = 0
    @State private var dismissTick: Int = 0

    private let autoTimeoutDuration: Double = 10.0

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Theme helpers

    // Semantic tokens respect Dark Mode natively — FriendlyPalette dark
    // (#140a38) was bleeding purple into the screenshot banner.

    private var canvasColor: Color { Color.sysSecondaryBackground }
    private var textColor: Color { Color.sysLabel }
    private var textDimColor: Color { Color.sysSecondaryLabel }
    private var lineColor: Color { Color.sysSeparator }

    var body: some View {
        VStack(spacing: 0) {
            // Top row
            HStack(spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share this screenshot?")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(-14 * 0.01)
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                    Text("One tap creates a 24-hour link")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(textDimColor)
                }
                Spacer(minLength: 6)
            }

            // Button row
            HStack(spacing: 8) {
                // Dismiss button
                Button(action: dismiss) {
                    Text("Dismiss")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(textDimColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(lineColor, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                // Share button (wider)
                Button(action: upload) {
                    Text("Share it")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 12)

            // Drain rail
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(lineColor)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(BrandPalette.accentHot)
                        .frame(width: geo.size.width * CGFloat(drainProgress), height: 3)
                }
            }
            .frame(height: 3)
            .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(canvasColor)
                .shadow(color: Color(red: 33/255, green: 18/255, blue: 68/255).opacity(0.08), radius: 16, x: 0, y: 4)
                .shadow(color: Color(red: 33/255, green: 18/255, blue: 68/255).opacity(0.06), radius: 48, x: 0, y: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(lineColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .sensoryFeedback(.impact(weight: .medium), trigger: uploadTick)
        .sensoryFeedback(.impact(weight: .light), trigger: dismissTick)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Screenshot ready to share")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            // Kick off the drain animation immediately
            withAnimation(.linear(duration: autoTimeoutDuration)) {
                drainProgress = 0.0
            }
            // Auto-dismiss after timeout
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(autoTimeoutDuration * 1_000_000_000))
                onDismiss()
            }
        }
    }

    // MARK: - Thumbnail

    private var thumbnail: some View {
        Group {
            if let image = UIImage(contentsOfFile: pending.url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BrandPalette.accentHot.opacity(0.25))
                    .overlay(
                        Text("📸")
                            .font(.system(size: 20))
                    )
            }
        }
        .frame(width: 44, height: 58)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BrandPalette.accentHot.opacity(0.40), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func upload() {
        uploadTick &+= 1
        onUpload()
    }

    private func dismiss() {
        dismissTick &+= 1
        onDismiss()
    }
}
#endif
