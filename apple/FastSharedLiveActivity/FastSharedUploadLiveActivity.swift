import ActivityKit
import SwiftUI
import WidgetKit
import FastSharedCore

#if canImport(UIKit)
import UIKit
#endif

struct FastSharedUploadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastSharedActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .widgetURL(URL(string: "fastshared://jobs/\(context.attributes.clientJobId.uuidString)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeading(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailing(state: context.state, attributes: context.attributes)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                CompactLeadingView(state: context.state)
            } compactTrailing: {
                CompactTrailingView(state: context.state)
            } minimal: {
                MinimalView(state: context.state)
            }
            .widgetURL(URL(string: "fastshared://jobs/\(context.attributes.clientJobId.uuidString)"))
            .keylineTint(FriendlyPalette.accentHot)
        }
    }
}

// MARK: - Lock Screen / Banner

private struct LockScreenView: View {
    let attributes: FastSharedActivityAttributes
    let state: FastSharedActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            LockFileChip(contentType: attributes.contentType, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(attributes.filename)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrandPalette.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    LARetentionBadge(text: attributes.retentionBadge)
                }
                lockBody
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(BrandPalette.ground)
    }

    @ViewBuilder
    private var lockBody: some View {
        switch state.phase {
        case .uploading:
            VStack(alignment: .leading, spacing: 4) {
                // Progress bar: track 6pt, radius 3, fill accentHot
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(FriendlyPalette.accentHot)
                            .frame(width: geo.size.width * CGFloat(max(0, min(1, state.progress))), height: 5)
                    }
                }
                .frame(height: 5)

                HStack {
                    Text(byteCountText(sent: state.bytesSent, total: state.bytesTotal))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(BrandPalette.text.opacity(0.60))
                    Spacer()
                    Text("\(Int((state.progress * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(FriendlyPalette.accentHot)
                }
            }
        case .completed:
            if let shortUrl = state.shortUrl {
                HStack(spacing: 6) {
                    Text("✓")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(FriendlyPalette.successGreen)
                    Text(shortUrl)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(BrandPalette.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    if let expiresAt = state.expiresAt {
                        Text(expiresAt, style: .timer)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(FriendlyPalette.accentSoft)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Text("✓")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(FriendlyPalette.successGreen)
                    Text("Link copied")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BrandPalette.text)
                    Spacer()
                    LARetentionBadge(text: attributes.retentionBadge)
                }
            }
        case .failed:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FriendlyPalette.UrgencyTier.critical.text)
                Text(state.errorReason ?? "Upload failed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BrandPalette.text.opacity(0.85))
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Dynamic Island: Expanded regions

// WHY: the Dynamic Island's expanded region is split into three slots —
// leading, trailing, and bottom. Apple sizes leading and trailing around the
// TrueDepth camera cutout, so anything we cram in leading (chip + filename +
// progress) gets compressed to the point of rendering as a grey blob. We keep
// leading to a single 40–44 pt icon and push filename / progress into the
// full-width `ExpandedBottom` where there's breathing room.

private struct ExpandedLeading: View {
    let attributes: FastSharedActivityAttributes
    let state: FastSharedActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .uploading:
            LAFileChip(contentType: attributes.contentType, size: 40)
                .padding(.leading, 4)

        case .completed:
            ZStack {
                Circle()
                    .fill(FriendlyPalette.successGreen)
                    .frame(width: 36, height: 36)
                Text("✓")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 4)

        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(FriendlyPalette.UrgencyTier.critical.text)
                .padding(.leading, 4)
        }
    }
}

private struct ExpandedTrailing: View {
    let state: FastSharedActivityAttributes.ContentState
    let attributes: FastSharedActivityAttributes

    var body: some View {
        switch state.phase {
        case .uploading:
            Text("\(Int((state.progress * 100).rounded()))%")
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                .foregroundStyle(FriendlyPalette.accentHot)
                .contentTransition(.numericText())
                .padding(.trailing, 4)

        case .completed:
            LARetentionBadge(text: attributes.retentionBadge)
                .padding(.trailing, 4)

        case .failed:
            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(FriendlyPalette.accentHot)
                .padding(.trailing, 4)
        }
    }
}

private struct ExpandedBottom: View {
    let attributes: FastSharedActivityAttributes
    let state: FastSharedActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .uploading:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(attributes.filename)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(byteCountText(sent: state.bytesSent, total: state.bytesTotal))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.60))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(FriendlyPalette.accentHot)
                            .frame(
                                width: max(6, geo.size.width * CGFloat(max(0, min(1, state.progress)))),
                                height: 6
                            )
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

        case .completed:
            if let shortUrl = state.shortUrl {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FriendlyPalette.accentHot)
                    Text(shortUrl)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if let expiresAt = state.expiresAt {
                        Text(expiresAt, style: .timer)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(FriendlyPalette.accentSoft)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }

        case .failed:
            HStack(spacing: 8) {
                Text(state.errorReason ?? "Upload failed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(2)
                Spacer()
                Link(destination: URL(string: "fastshared://jobs/\(attributes.clientJobId.uuidString)")!) {
                    Text("Retry")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(FriendlyPalette.accentHot, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
    }
}

// MARK: - Dynamic Island: Compact & Minimal

private struct CompactLeadingView: View {
    let state: FastSharedActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .uploading:
            // Ring progress + percent
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(FriendlyPalette.accentHot.opacity(0.25), lineWidth: 2.5)
                        .frame(width: 20, height: 20)
                    Circle()
                        .trim(from: 0, to: max(0.04, min(1, state.progress)))
                        .stroke(FriendlyPalette.accentHot, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 20, height: 20)
                }

                Text("\(Int((state.progress * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(FriendlyPalette.accentHot)
                    .contentTransition(.numericText())
            }

        case .completed:
            ZStack {
                Circle()
                    .fill(FriendlyPalette.successGreen)
                    .frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
            }

        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FriendlyPalette.UrgencyTier.critical.text)
        }
    }
}

private struct CompactTrailingView: View {
    let state: FastSharedActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .uploading:
            // File type emoji (14pt) on right
            Text("📎")
                .font(.system(size: 14))

        case .completed:
            Image(systemName: "paperplane.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FriendlyPalette.successGreen)

        case .failed:
            Text("!")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(FriendlyPalette.UrgencyTier.critical.text)
        }
    }
}

private struct MinimalView: View {
    let state: FastSharedActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .uploading:
            Image(systemName: "paperplane.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FriendlyPalette.accentHot)
        case .completed:
            Image(systemName: "paperplane.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FriendlyPalette.successGreen)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FriendlyPalette.UrgencyTier.critical.text)
        }
    }
}

// MARK: - Shared parts

/// 56×56 (or configurable) file chip for the Dynamic Island expanded view.
private struct LAFileChip: View {
    let contentType: String
    var size: CGFloat = 56

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(FriendlyPalette.accentHot.opacity(0.20))
            .frame(width: size, height: size)
            .overlay(
                Text(fileEmoji)
                    .font(.system(size: 24))
            )
    }

    private var fileEmoji: String {
        if contentType.hasPrefix("image/") { return "🖼️" }
        if contentType.hasPrefix("video/") { return "🎬" }
        if contentType.hasPrefix("audio/") { return "🎵" }
        if contentType == "application/pdf" { return "📄" }
        return "📎"
    }
}

/// 48×48 file chip for lock screen view.
private struct LockFileChip: View {
    let contentType: String
    var size: CGFloat = 48

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(FriendlyPalette.accentHot.opacity(0.20))
            .frame(width: size, height: size)
            .overlay(
                Text(fileEmoji)
                    .font(.system(size: 20))
            )
    }

    private var fileEmoji: String {
        if contentType.hasPrefix("image/") { return "🖼️" }
        if contentType.hasPrefix("video/") { return "🎬" }
        if contentType.hasPrefix("audio/") { return "🎵" }
        if contentType == "application/pdf" { return "📄" }
        return "📎"
    }
}

/// Plane+Arc mark — inline re-declaration for the Live Activity target
/// (widget extensions can't link the app-target `PlaneArcMark`).
private struct LAPlaneArc: View {
    var size: CGFloat = 44

    var body: some View {
        let a = BrandPalette.violetAccent
        let arcStrokeWidth = size * (9.0 / 140.0)

        ZStack {
            LAArcPath()
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: a.fade.opacity(0), location: 0),
                            .init(color: a.hot.opacity(0.95), location: 0.5),
                            .init(color: a.soft, location: 1),
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    style: StrokeStyle(lineWidth: arcStrokeWidth, lineCap: .round)
                )
                .frame(width: size, height: size)

            GeometryReader { geo in
                let s = geo.size.width / 140.0
                let transform = CGAffineTransform(translationX: 84 * s, y: 64 * s)
                    .scaledBy(x: 1.1 * s, y: 1.1 * s)
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 0).applying(transform))
                        p.addLine(to: CGPoint(x: 22, y: -26).applying(transform))
                        p.addLine(to: CGPoint(x: 14, y: 10).applying(transform))
                        p.addLine(to: CGPoint(x: 4, y: 4).applying(transform))
                        p.addLine(to: CGPoint(x: 0, y: 18).applying(transform))
                        p.addLine(to: CGPoint(x: -4, y: 4).applying(transform))
                        p.closeSubpath()
                    }
                    .fill(BrandPalette.text)
                    Path { p in
                        p.move(to: CGPoint(x: 4, y: 4).applying(transform))
                        p.addLine(to: CGPoint(x: 14, y: 10).applying(transform))
                    }
                    .stroke(BrandPalette.text.opacity(0.35), lineWidth: 1)
                }
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}

private struct LAArcPath: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 140.0
        var p = Path()
        p.move(to: CGPoint(x: 26 * s, y: 110 * s))
        p.addQuadCurve(
            to: CGPoint(x: 82 * s, y: 68 * s),
            control: CGPoint(x: 60 * s, y: 98 * s)
        )
        return p
    }
}

/// Retention badge pill — violet accentHot background.
private struct LARetentionBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(FriendlyPalette.accentHot, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private func byteCountText(sent: Int64, total: Int64) -> String {
    if total <= 0 {
        return ByteCountFormatter.string(fromByteCount: sent, countStyle: .file)
    }
    let sentStr = ByteCountFormatter.string(fromByteCount: sent, countStyle: .file)
    let totalStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    return "\(sentStr) / \(totalStr)"
}
