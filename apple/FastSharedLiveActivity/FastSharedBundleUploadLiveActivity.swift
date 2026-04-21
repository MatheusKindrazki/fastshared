import ActivityKit
import SwiftUI
import WidgetKit
import FastSharedCore

#if canImport(UIKit)
import UIKit
#endif

/// Bundle (multi-file) upload Live Activity. Mirrors the single-file widget
/// layout so the user sees a familiar shape when sharing 1 vs N files; only
/// the headline + body content differ.
struct FastSharedBundleUploadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BundleUploadAttributes.self) { context in
            BundleLockScreenView(attributes: context.attributes, state: context.state)
                .widgetURL(URL(string: "fastshared://bundles/\(context.attributes.bundleToken)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BundleExpandedLeading(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BundleExpandedTrailing(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    BundleExpandedBottom(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                BundleCompactLeading(attributes: context.attributes, state: context.state)
            } compactTrailing: {
                BundleCompactTrailing(state: context.state)
            } minimal: {
                BundleMinimalView(state: context.state)
            }
            .widgetURL(URL(string: "fastshared://bundles/\(context.attributes.bundleToken)"))
            .keylineTint(FriendlyPalette.accentHot)
        }
    }
}

// MARK: - Lock Screen / Banner

private struct BundleLockScreenView: View {
    let attributes: BundleUploadAttributes
    let state: BundleUploadAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BundleStackChip(count: attributes.fileCount, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(headline)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrandPalette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    BundleRetentionBadge(text: attributes.retentionBadge)
                }
                bundleBody
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(BrandPalette.ground)
    }

    private var headline: String {
        switch state.phase {
        case .uploading: return "Sending \(attributes.fileCount) files"
        case .completed: return "\(attributes.fileCount) files shared"
        case .failed:    return "Bundle upload failed"
        }
    }

    @ViewBuilder
    private var bundleBody: some View {
        switch state.phase {
        case .uploading:
            VStack(alignment: .leading, spacing: 6) {
                BundleProgressBar(progress: state.progress)
                HStack {
                    Text(byteCountText(sent: state.bytesUploaded, total: attributes.totalBytes))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(BrandPalette.text.opacity(0.60))
                    Spacer()
                    Text("\(Int((state.progress * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(FriendlyPalette.accentHot)
                }
                BundleFilenameList(filenames: attributes.filenames,
                                   totalCount: attributes.fileCount,
                                   compact: true)
            }

        case .completed:
            if let url = state.bundleShortUrl {
                HStack(spacing: 6) {
                    Text("✓")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(FriendlyPalette.successGreen)
                    Text(url)
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
                    Text("Bundle link copied")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BrandPalette.text)
                    Spacer()
                    BundleRetentionBadge(text: attributes.retentionBadge)
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

// MARK: - Dynamic Island

// Same compression rationale as the single-upload widget: leading region is
// next to the camera cutout, so we keep it to a single 40-44pt chip and push
// the headline / progress into the full-width bottom slot.

private struct BundleExpandedLeading: View {
    let state: BundleUploadAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .uploading:
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(FriendlyPalette.accentHot.opacity(0.20))
                    .frame(width: 40, height: 40)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FriendlyPalette.accentHot)
            }
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

private struct BundleExpandedTrailing: View {
    let attributes: BundleUploadAttributes
    let state: BundleUploadAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .uploading:
            Text("\(Int((state.progress * 100).rounded()))%")
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                .foregroundStyle(FriendlyPalette.accentHot)
                .contentTransition(.numericText())
                .padding(.trailing, 4)

        case .completed:
            BundleRetentionBadge(text: attributes.retentionBadge)
                .padding(.trailing, 4)

        case .failed:
            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(FriendlyPalette.accentHot)
                .padding(.trailing, 4)
        }
    }
}

private struct BundleExpandedBottom: View {
    let attributes: BundleUploadAttributes
    let state: BundleUploadAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .uploading:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Sending \(attributes.fileCount) files")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(byteCountText(sent: state.bytesUploaded, total: attributes.totalBytes))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.60))
                }
                BundleProgressBar(progress: state.progress, height: 6)
                BundleFilenameList(filenames: attributes.filenames,
                                   totalCount: attributes.fileCount,
                                   compact: false)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

        case .completed:
            if let url = state.bundleShortUrl {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FriendlyPalette.accentHot)
                    Text(url)
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
                Text(state.errorReason ?? "Bundle upload failed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
    }
}

private struct BundleCompactLeading: View {
    let attributes: BundleUploadAttributes
    let state: BundleUploadAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .uploading:
            HStack(spacing: 5) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FriendlyPalette.accentHot)
                Text("\(attributes.fileCount)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(BrandPalette.text)
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

private struct BundleCompactTrailing: View {
    let state: BundleUploadAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .uploading:
            Text("\(Int((state.progress * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(FriendlyPalette.accentHot)
                .contentTransition(.numericText())

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

private struct BundleMinimalView: View {
    let state: BundleUploadAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .uploading:
            Text("\(Int((state.progress * 100).rounded()))%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
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

private struct BundleStackChip: View {
    let count: Int
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FriendlyPalette.accentHot.opacity(0.20))
                .frame(width: size, height: size)
            VStack(spacing: 2) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: size * 0.40, weight: .semibold))
                    .foregroundStyle(FriendlyPalette.accentHot)
                Text("\(count)")
                    .font(.system(size: size * 0.22, weight: .heavy).monospacedDigit())
                    .foregroundStyle(FriendlyPalette.accentHot)
            }
        }
    }
}

private struct BundleProgressBar: View {
    let progress: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: height)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(FriendlyPalette.accentHot)
                    .frame(width: max(height, geo.size.width * CGFloat(max(0, min(1, progress)))),
                           height: height)
            }
        }
        .frame(height: height)
    }
}

/// Top-3 filenames + "+N more" tail. Compact mode flattens to a single line.
private struct BundleFilenameList: View {
    let filenames: [String]
    let totalCount: Int
    let compact: Bool

    private var visible: [String] { Array(filenames.prefix(3)) }
    private var overflow: Int { max(0, totalCount - visible.count) }

    var body: some View {
        if compact {
            // One line, comma-separated, truncated. Cheap on lock screen.
            Text(joinedText)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(BrandPalette.text.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if overflow > 0 {
                    Text("+\(overflow) more")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(FriendlyPalette.accentSoft)
                }
            }
        }
    }

    private var joinedText: String {
        var parts = visible
        if overflow > 0 { parts.append("+\(overflow)") }
        return parts.joined(separator: ", ")
    }
}

private struct BundleRetentionBadge: View {
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
