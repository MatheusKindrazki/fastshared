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
            .keylineTint(BrandPalette.amberAccent.hot)
        }
    }
}

// MARK: - Lock Screen / Banner

private struct LockScreenView: View {
    let attributes: FastSharedActivityAttributes
    let state: FastSharedActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            // v3 lock-screen hero — Plane + Arc sits in place of the old halo
            // glyph during uploading/completed. For `.failed` we fall back to
            // the triangle warning since the mark alone doesn't read as error.
            LockHero(state: state)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(attributes.filename)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrandPalette.text)
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
        .background(BrandPalette.ground)
    }

    @ViewBuilder
    private var lockBody: some View {
        switch state.phase {
        case .uploading:
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: max(0, min(1, state.progress)))
                    .progressViewStyle(.linear)
                    .tint(BrandPalette.amberAccent.hot)
                HStack {
                    Text(byteCountText(sent: state.bytesSent, total: state.bytesTotal))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(BrandPalette.text.opacity(0.65))
                    Spacer()
                    Text("\(Int((state.progress * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(BrandPalette.amberAccent.hot)
                }
            }
        case .completed:
            if let shortUrl = state.shortUrl, let url = URL(string: shortUrl) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BrandPalette.amberAccent.hot)
                    Text(url.host.map { "\($0)\(url.path)" } ?? shortUrl)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(BrandPalette.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    if let expiresAt = state.expiresAt {
                        Text(expiresAt, style: .timer)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(BrandPalette.amberAccent.dust)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        case .failed:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BrandPalette.amberAccent.fade)
                Text(state.errorReason ?? "Upload failed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BrandPalette.text.opacity(0.85))
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
            // v3 expanded leading — compact Plane + Arc glyph replaces the
            // paperplane SF Symbol. The mark itself carries the brand signal;
            // 18pt matches the density of the adjacent text.
            LAPlaneArc(size: 18)
                .accessibilityHidden(true)
            Text(attributes.filename)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BrandPalette.text)
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
                    .tint(BrandPalette.amberAccent.hot)
                HStack {
                    Text(byteCountText(sent: state.bytesSent, total: state.bytesTotal))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(BrandPalette.text.opacity(0.7))
                    Spacer()
                    Text("\(Int((state.progress * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(BrandPalette.amberAccent.hot)
                }
            }
            .padding(.top, 2)
        case .completed:
            VStack(alignment: .leading, spacing: 6) {
                if let shortUrl = state.shortUrl {
                    Link(destination: URL(string: shortUrl) ?? URL(string: "https://fastsha.red")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .semibold))
                            Text(shortUrl)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(BrandPalette.ground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(BrandPalette.surface0)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(BrandPalette.arc, lineWidth: 1)
                                )
                        )
                    }
                }
                if let expiresAt = state.expiresAt {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(BrandPalette.amberAccent.fade)
                        Text("expires in ")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(BrandPalette.text.opacity(0.6))
                        Text(expiresAt, style: .timer)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(BrandPalette.amberAccent.dust)
                    }
                }
            }
            .padding(.top, 2)
        case .failed:
            HStack(spacing: 8) {
                Text(state.errorReason ?? "Upload failed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BrandPalette.text.opacity(0.85))
                    .lineLimit(2)
                Spacer()
                Link(destination: URL(string: "fastshared://jobs/\(attributes.clientJobId.uuidString)")!) {
                    Text("Retry")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BrandPalette.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(BrandPalette.amberAccent.hot, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            // v3 compact leading while uploading — plane+arc mark with a
            // subtle ring overlay showing progress. The mark carries the
            // brand; the thin ring is functional.
            ZStack {
                LAPlaneArc(size: 18)
                Circle()
                    .trim(from: 0, to: max(0.04, min(1, state.progress)))
                    .stroke(
                        BrandPalette.amberAccent.hot.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 18, height: 18)
            }
            .frame(width: 18, height: 18)
        case .completed:
            ZStack {
                Circle().fill(BrandPalette.amberAccent.hot)
                    .frame(width: 18, height: 18)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.white)
            }
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BrandPalette.amberAccent.fade)
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
                .foregroundStyle(BrandPalette.amberAccent.hot)
                .contentTransition(.numericText())
        case .completed:
            Text(slug(from: state.shortUrl))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(BrandPalette.amberAccent.dust)
                .lineLimit(1)
        case .failed:
            Text("FAILED")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(BrandPalette.amberAccent.fade)
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
                .foregroundStyle(BrandPalette.amberAccent.hot)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BrandPalette.amberAccent.fade)
        }
    }
}

// MARK: - Shared parts

/// Lock-screen hero composition — v3 Plane + Arc sits in a 44pt tile during
/// uploading (with a functional ring overlay) and completed. Failure falls
/// back to the triangle warning against a coral wash.
private struct LockHero: View {
    let state: FastSharedActivityAttributes.ContentState

    var body: some View {
        ZStack {
            switch state.phase {
            case .uploading:
                LAPlaneArc(size: 44)
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, state.progress)))
                    .stroke(
                        BrandPalette.amberAccent.hot,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(2)
            case .completed:
                LAPlaneArc(size: 44)
            case .failed:
                Circle().fill(BrandPalette.amberAccent.fade.opacity(0.2))
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(BrandPalette.amberAccent.fade)
            }
        }
    }
}

/// Plane+Arc mark — inline re-declaration for the Live Activity target
/// (widget extensions can't link the app-target `PlaneArcMark`). Same
/// viewBox-140 coordinates, same dart path, same gradient stops.
private struct LAPlaneArc: View {
    var size: CGFloat = 44

    var body: some View {
        let a = BrandPalette.amberAccent
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

private struct RetentionBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(BrandPalette.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(BrandPalette.amberAccent.hot, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Compact amber progress ring — same visual language as the share extension success hero.
private struct AmberRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(BrandPalette.amberAccent.hot.opacity(0.25), lineWidth: 2.5)
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
