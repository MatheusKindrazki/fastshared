#if os(iOS)
import SwiftUI
import UIKit
import FastSharedCore

/// Soft nudge that slides in from the top of the hub when the user takes a screenshot.
/// 10s auto-dismiss. Tap Upload to feed it into the pipeline; tap Dismiss to hide.
@MainActor
struct ScreenshotBanner: View {
    let pending: PendingScreenshot
    let onUpload: () -> Void
    let onDismiss: () -> Void

    // WHY: `Date.now` captured at render instantiation gives the TimelineView a stable origin for
    // the 10-second countdown without needing an external clock.
    @State private var shownAt: Date = .now
    @State private var uploadTick: Int = 0
    @State private var dismissTick: Int = 0

    private let lifetime: TimeInterval = 10

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            let elapsed = max(0, ctx.date.timeIntervalSince(shownAt))
            let remainingFraction = max(0, min(1, (lifetime - elapsed) / lifetime))

            content(remainingFraction: remainingFraction)
                .onChange(of: elapsed) { _, newValue in
                    if newValue >= lifetime {
                        onDismiss()
                    }
                }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: uploadTick)
        .sensoryFeedback(.impact(weight: .light), trigger: dismissTick)
    }

    @ViewBuilder
    private func content(remainingFraction: Double) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screenshot · ready to share")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrandPalette.milk)
                        .lineLimit(1)
                    Text("Tap to upload")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(BrandPalette.amber)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                buttons
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Progress rail drains over the 10s lifetime; visual reinforcement for auto-dismiss.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(BrandPalette.amber.opacity(0.08))
                    Rectangle()
                        .fill(BrandPalette.amber)
                        .frame(width: geo.size.width * remainingFraction)
                }
            }
            .frame(height: 2)
            .clipShape(Capsule())
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(BrandPalette.nightshade)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(BrandPalette.amber.opacity(0.8), lineWidth: 1)
                )
        )
        .shadow(color: BrandPalette.ink.opacity(0.45), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Screenshot ready to share")
        .accessibilityAddTraits(.isButton)
    }

    private var thumbnail: some View {
        Group {
            if let image = UIImage(contentsOfFile: pending.url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BrandPalette.violet.opacity(0.55))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(BrandPalette.ember)
                    )
            }
        }
        .frame(width: 44, height: 44)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(BrandPalette.amber.opacity(0.25), lineWidth: 0.5)
        )
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button(action: upload) {
                Text("Upload")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BrandPalette.ink)
                    .frame(height: 28)
                    .padding(.horizontal, 12)
                    .background(BrandPalette.amber, in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: dismiss) {
                Text("Dismiss")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BrandPalette.milk.opacity(0.6))
                    .frame(height: 28)
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)
        }
    }

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
