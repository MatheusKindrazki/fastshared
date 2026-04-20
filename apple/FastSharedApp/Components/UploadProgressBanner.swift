import SwiftUI
import FastSharedCore

#if canImport(UIKit)
import UIKit
#endif

/// In-app fallback for upload feedback. Mirrors the visual register of
/// `ScreenshotBanner` so they read as part of the same family. Driven by
/// `UploadProgressMonitor.shared.current`. Three states: uploading, completed,
/// failed. Tap to dismiss; for the completed state, tap re-copies the link.
@MainActor
struct UploadProgressBanner: View {
    let upload: UploadProgressMonitor.ActiveUpload

    @Environment(\.colorScheme) private var colorScheme

    // MARK: Theme helpers

    private var paperColor: Color { FriendlyPalette.paper(colorScheme) }
    private var textColor: Color { FriendlyPalette.text(colorScheme) }
    private var textDimColor: Color { FriendlyPalette.textDim(colorScheme) }
    private var lineStrongColor: Color { FriendlyPalette.lineStrong(colorScheme) }

    private var accentColor: Color {
        switch upload.phase {
        case .uploading: return FriendlyPalette.accentHot
        case .completed: return FriendlyPalette.successGreen
        case .failed:    return FriendlyPalette.accentFade
        }
    }

    // MARK: Layout

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let sub = subline {
                        Text(sub)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(textDimColor)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
            }
            .padding(.horizontal, FriendlyPalette.Spacing.md)
            .padding(.vertical, FriendlyPalette.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: FriendlyPalette.Radius.lg, style: .continuous)
                    .fill(paperColor)
                    .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: FriendlyPalette.Radius.lg, style: .continuous)
                    .stroke(lineStrongColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: FriendlyPalette.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Leading glyph

    @ViewBuilder
    private var leading: some View {
        switch upload.phase {
        case .uploading:
            Ring(progress: upload.progress, size: 28, stroke: 3, tint: accentColor)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(accentColor)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(accentColor)
        }
    }

    // MARK: Copy

    private var headline: String {
        switch upload.phase {
        case .uploading:
            // Tier 1: presign returns an optimistic short URL that gets
            // copied immediately; banner acknowledges the copy while bytes
            // continue to flow.
            if upload.linkReady {
                return "Link copied — still uploading"
            }
            return upload.filename.isEmpty ? "Uploading…" : upload.filename
        case .completed:
            return "Link copied"
        case .failed:
            return upload.error ?? "Upload failed"
        }
    }

    private var subline: String? {
        switch upload.phase {
        case .uploading:
            if upload.bytesTotal > 0 {
                return "\(formatted(upload.bytesSent)) / \(formatted(upload.bytesTotal))"
            }
            return "\(Int(upload.progress * 100))%"
        case .completed:
            return upload.filename.isEmpty ? nil : upload.filename
        case .failed:
            return upload.filename.isEmpty ? nil : upload.filename
        }
    }

    private var accessibilityLabel: String {
        switch upload.phase {
        case .uploading:
            let percent = Int(upload.progress * 100)
            let name = upload.filename.isEmpty ? "file" : upload.filename
            return "Uploading \(name), \(percent) percent"
        case .completed:
            return "Link copied to clipboard"
        case .failed:
            return "Upload failed: \(upload.error ?? "unknown error")"
        }
    }

    // MARK: Behaviour

    private func handleTap() {
        if upload.phase == .completed, let url = upload.shortUrl {
            #if canImport(UIKit)
            UIPasteboard.general.string = url
            #endif
        }
        UploadProgressMonitor.shared.dismiss()
    }

    // MARK: Helpers

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
