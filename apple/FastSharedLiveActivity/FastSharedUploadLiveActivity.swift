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
                    ExpandedLeading(attributes: context.attributes)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RetentionBadge(text: context.attributes.retentionBadge)
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
            .keylineTint(BrandPalette.amber)
        }
    }
}

// MARK: - Lock Screen / Banner

private struct LockScreenView: View {
    let attributes: FastSharedActivityAttributes
    let state: FastSharedActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            HeroGlyph(state: state)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(attributes.filename)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrandPalette.milk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    RetentionBadge(text: attributes.retentionBadge)
                }
                lockBody
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(BrandPalette.canvas)
    }

    @ViewBuilder
    private var lockBody: some View {
        switch state.phase {
        case .uploading:
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: max(0, min(1, state.progress)))
                    .progressViewStyle(.linear)
                    .tint(BrandPalette.amber)
                HStack {
                    Text(byteCountText(sent: state.bytesSent, total: state.bytesTotal))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(BrandPalette.milk.opacity(0.65))
                    Spacer()
                    Text("\(Int((state.progress * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(BrandPalette.amber)
                }
            }
        case .completed:
            if let shortUrl = state.shortUrl, let url = URL(string: shortUrl) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BrandPalette.amber)
                    Text(url.host.map { "\($0)\(url.path)" } ?? shortUrl)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(BrandPalette.milk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    if let expiresAt = state.expiresAt {
                        Text(expiresAt, style: .timer)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(BrandPalette.dust)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        case .failed:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BrandPalette.coral)
                Text(state.errorReason ?? "Upload failed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BrandPalette.milk.opacity(0.85))
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Dynamic Island regions

private struct ExpandedLeading: View {
    let attributes: FastSharedActivityAttributes

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BrandPalette.amber)
            Text(attributes.filename)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BrandPalette.milk)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct ExpandedBottom: View {
    let attributes: FastSharedActivityAttributes
    let state: FastSharedActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .uploading:
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: max(0, min(1, state.progress)))
                    .progressViewStyle(.linear)
                    .tint(BrandPalette.amber)
                HStack {
                    Text(byteCountText(sent: state.bytesSent, total: state.bytesTotal))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(BrandPalette.milk.opacity(0.7))
                    Spacer()
                    Text("\(Int((state.progress * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(BrandPalette.amber)
                }
            }
            .padding(.top, 2)
        case .completed:
            VStack(alignment: .leading, spacing: 6) {
                if let shortUrl = state.shortUrl {
                    Link(destination: URL(string: shortUrl) ?? URL(string: "https://fsh.re")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .semibold))
                            Text(shortUrl)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(BrandPalette.milk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(BrandPalette.nightshade)
                                .overlay(Capsule().strokeBorder(BrandPalette.arc, lineWidth: 1))
                        )
                    }
                }
                if let expiresAt = state.expiresAt {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(BrandPalette.coral)
                        Text("expires in ")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(BrandPalette.milk.opacity(0.6))
                        Text(expiresAt, style: .timer)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(BrandPalette.dust)
                    }
                }
            }
            .padding(.top, 2)
        case .failed:
            HStack(spacing: 8) {
                Text(state.errorReason ?? "Upload failed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BrandPalette.milk.opacity(0.85))
                    .lineLimit(2)
                Spacer()
                Link(destination: URL(string: "fastshared://jobs/\(attributes.clientJobId.uuidString)")!) {
                    Text("Retry")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BrandPalette.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(BrandPalette.amber, in: Capsule())
                }
            }
            .padding(.top, 2)
        }
    }
}

private struct CompactLeadingView: View {
    let state: FastSharedActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .uploading:
            AmberRing(progress: state.progress)
                .frame(width: 18, height: 18)
        case .completed:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(BrandPalette.amber)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BrandPalette.coral)
        }
    }
}

private struct CompactTrailingView: View {
    let state: FastSharedActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .uploading:
            Text("\(Int((state.progress * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(BrandPalette.amber)
                .contentTransition(.numericText())
        case .completed:
            Text(slug(from: state.shortUrl))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(BrandPalette.dust)
                .lineLimit(1)
        case .failed:
            Text("Failed")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BrandPalette.coral)
        }
    }

    private func slug(from urlString: String?) -> String {
        guard let urlString, let url = URL(string: urlString) else { return "" }
        let path = url.path
        if path.isEmpty || path == "/" { return url.host ?? "" }
        return path.hasPrefix("/") ? path : "/\(path)"
    }
}

private struct MinimalView: View {
    let state: FastSharedActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .uploading:
            AmberRing(progress: state.progress)
                .frame(width: 16, height: 16)
        case .completed:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(BrandPalette.amber)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BrandPalette.coral)
        }
    }
}

// MARK: - Shared parts

private struct HeroGlyph: View {
    let state: FastSharedActivityAttributes.ContentState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch state.phase {
            case .uploading:
                Circle()
                    .fill(BrandPalette.amber.opacity(0.18))
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, state.progress)))
                    .stroke(BrandPalette.arc, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(3)
                Circle()
                    .fill(RadialGradient(colors: [BrandPalette.ember, BrandPalette.amber],
                                         center: .center,
                                         startRadius: 0,
                                         endRadius: 18))
                    .padding(10)
            case .completed:
                Circle().fill(BrandPalette.amber.opacity(0.22))
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(BrandPalette.amber)
            case .failed:
                Circle().fill(BrandPalette.coral.opacity(0.2))
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(BrandPalette.coral)
            }
        }
    }
}

private struct RetentionBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(BrandPalette.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(BrandPalette.amber, in: Capsule())
    }
}

/// Compact amber progress ring — same visual language as the share extension success hero.
private struct AmberRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(BrandPalette.amber.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.04, min(1, progress)))
                .stroke(BrandPalette.arc, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
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
