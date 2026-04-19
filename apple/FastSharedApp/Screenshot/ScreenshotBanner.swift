#if os(iOS)
import SwiftUI
import UIKit
import FastSharedCore

/// Soft nudge that slides in from the top of the hub when the user takes a
/// screenshot. 10s auto-dismiss. Tap Upload to feed it into the pipeline;
/// tap the × to hide. Layout ported from `design/screens.jsx` →
/// `ScreenshotBanner()`.
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
        let accent = BrandPalette.amberAccent

        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screenshot ready")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrandPalette.text)
                        .lineLimit(1)
                    Text("TAP UPLOAD · AUTO-HIDE 10S")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(accent.hot)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                uploadButton
                dismissButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            // Drain rail — amber fills from left and shrinks as the 10s countdown progresses.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(BrandPalette.line)
                    Rectangle()
                        .fill(accent.hot)
                        .frame(width: geo.size.width * remainingFraction)
                }
            }
            .frame(height: 2)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BrandPalette.surface1.opacity(0.92))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BrandPalette.lineStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Screenshot ready to share")
        .accessibilityAddTraits(.isButton)
    }

    private var thumbnail: some View {
        let accent = BrandPalette.amberAccent
        return Group {
            if let image = UIImage(contentsOfFile: pending.url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [BrandPalette.surface1, BrandPalette.surface2],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(accent.hot)
                )
            }
        }
        .frame(width: 52, height: 52)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(accent.hot.opacity(0.20), lineWidth: 1)
        )
    }

    private var uploadButton: some View {
        let accent = BrandPalette.amberAccent
        return Button(action: upload) {
            Text("UPLOAD")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color(red: 0.07, green: 0.02, blue: 0.04))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(accent.hot, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var dismissButton: some View {
        Button(action: dismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BrandPalette.textDim)
                .padding(8)
        }
        .buttonStyle(.plain)
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
