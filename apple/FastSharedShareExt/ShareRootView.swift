import SwiftUI
import FastSharedCore

#if canImport(UIKit)
import UIKit
#endif

/// Share extension root — Friendly redesign.
///
/// Five phases backed by `ShareViewModel`. The sheet itself sits on top of a
/// faded host-app backdrop. All color tokens are read via `@Environment(\.colorScheme)`
/// so the sheet adapts to both light and dark appearances.
struct ShareRootView: View {
    @Bindable var viewModel: ShareViewModel
    /// Process-scoped coordinator owned by ShareViewController; shared here
    /// so a gated-retention tap triggers the paywall sheet below.
    @Bindable var paywallCoordinator: PaywallCoordinator
    let onUpload: () async -> Void
    let onCancel: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Dim the host context so the sheet reads as modal.
            LinearGradient(
                colors: [groundColor.opacity(0.6),
                         groundColor.opacity(0.85),
                         groundColor],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav bar
                navBar
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                content
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .background(groundColor, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(lineColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 32, y: -12)
            .padding(12)
            .frame(minWidth: 360)
        }
        .foregroundStyle(textColor)
        .animation(BrandMotion.transition, value: phaseKey)
        .sheet(item: $paywallCoordinator.pending) { trigger in
            SharePaywallSheet(trigger: trigger) {
                paywallCoordinator.dismiss()
            }
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentHot)
            }
            .buttonStyle(.plain)

            Spacer()

            SheetBrandLockup(markSize: 22, textSize: 15)

            Spacer()

            // Mirror Cancel width for centering
            Text("Cancel")
                .font(.system(size: 15, weight: .semibold))
                .opacity(0)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Phase key

    private var phaseKey: Int {
        switch viewModel.phase {
        case .idle: return 0
        case .preparing: return 1
        case .uploading: return 2
        case .success: return 3
        case .failed: return 4
        }
    }

    // MARK: - Content routing

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            IdleStage(viewModel: viewModel,
                      paywallCoordinator: paywallCoordinator,
                      onUpload: onUpload,
                      onCancel: onCancel)
        case .preparing:
            IdleStage(viewModel: viewModel,
                      paywallCoordinator: paywallCoordinator,
                      onUpload: onUpload,
                      onCancel: onCancel,
                      isPreparing: true)
        case .uploading(let progress, let sent, let total):
            IdleStage(viewModel: viewModel,
                      paywallCoordinator: paywallCoordinator,
                      onUpload: onUpload,
                      onCancel: onCancel,
                      uploadProgress: progress,
                      bytesSent: sent,
                      bytesTotal: total)
        case .success(let link, let filename, let deduped):
            SuccessStage(link: link,
                         filename: filename,
                         deduped: deduped,
                         retention: viewModel.retentionPolicy,
                         onDone: onDismiss)
        case .failed(let reason, let requestId):
            FailureStage(reason: reason,
                         requestId: requestId,
                         onRetry: { Task { await onUpload() } },
                         onCancel: onCancel)
        }
    }

    // MARK: - Theme helpers

    private var groundColor: Color     { FriendlyPalette.ground(colorScheme) }
    private var canvasColor: Color     { FriendlyPalette.canvas(colorScheme) }
    private var surface0Color: Color   { FriendlyPalette.surface0(colorScheme) }
    private var textColor: Color       { FriendlyPalette.text(colorScheme) }
    private var textDimColor: Color    { FriendlyPalette.textDim(colorScheme) }
    private var lineColor: Color       { FriendlyPalette.line(colorScheme) }
    private var lineStrongColor: Color { FriendlyPalette.lineStrong(colorScheme) }
    private var accentHot: Color       { FriendlyPalette.accentHot }
}

// MARK: - Shared inline atoms

/// Inline ring for the share extension (can't import app-target Components).
private struct SheetRing: View {
    let progress: Double
    var size: CGFloat = 54
    var stroke: CGFloat = 4

    private var clamped: Double { max(0.02, min(1, progress)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(FriendlyPalette.accentHot.opacity(0.22), lineWidth: stroke)
                .frame(width: size, height: size)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(FriendlyPalette.accentHot, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}

/// Inline plane-arc brand mark for the share extension.
///
/// Mirrors `apple/FastSharedApp/Components/PlaneArcMark.swift` — but this
/// target can't import Components, so we re-declare the v3 `PlaneArc` render
/// inline. Same viewBox-140 coordinates, same dart path, same gradient stops.
private struct SheetPlaneArc: View {
    var size: CGFloat = 80
    var framed: Bool = false
    var ambient: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var planeColor: Color { FriendlyPalette.text(colorScheme) }

    var body: some View {
        let corner = size * (32.0 / 140.0)
        let arcStrokeWidth = size * (9.0 / 140.0)
        let a = BrandPalette.violetAccent

        ZStack {
            if ambient {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [a.hot.opacity(0.21), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.82
                        )
                    )
                    .frame(width: size * 1.7, height: size * 1.7)
                    .blur(radius: 6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if framed {
                let bg = FriendlyPalette.surface0(colorScheme)
                let borderColor = FriendlyPalette.lineStrong(colorScheme)
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )
                    .frame(width: size, height: size)
            }

            SheetArcPath()
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
                    .fill(planeColor)
                    Path { p in
                        p.move(to: CGPoint(x: 4, y: 4).applying(transform))
                        p.addLine(to: CGPoint(x: 14, y: 10).applying(transform))
                    }
                    .stroke(planeColor.opacity(0.35), lineWidth: 1)
                }
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}

private struct SheetArcPath: Shape {
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

/// Inline brand lockup for the share extension.
private struct SheetBrandLockup: View {
    var markSize: CGFloat = 22
    var textSize: CGFloat = 15

    @Environment(\.colorScheme) private var colorScheme

    private var textColor: Color { FriendlyPalette.text(colorScheme) }

    var body: some View {
        HStack(spacing: 8) {
            SheetPlaneArc(size: markSize)
                .accessibilityHidden(true)
            (
                Text("fastshared")
                    .foregroundStyle(textColor)
                + Text(".")
                    .foregroundStyle(FriendlyPalette.accentHot)
            )
            .font(.system(size: textSize, weight: .bold))
            .tracking(-textSize * 0.02)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("fastshared")
    }
}

/// Inline file type icon tile.
private struct SheetFileIcon: View {
    let contentType: String
    var size: CGFloat = 48

    @Environment(\.colorScheme) private var colorScheme

    private var bg: Color { FriendlyPalette.surface0(colorScheme) }

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(bg)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.40, weight: .medium))
                    .foregroundStyle(FriendlyPalette.accentHot)
            )
    }

    private var symbolName: String {
        if contentType.hasPrefix("image/") { return "photo" }
        if contentType.hasPrefix("video/") { return "film" }
        if contentType.hasPrefix("audio/") { return "waveform" }
        if contentType == "application/pdf" { return "doc.richtext" }
        return "doc"
    }
}

// MARK: - Progress bar atom

private struct SheetProgressBar: View {
    let progress: Double   // 0…1

    @Environment(\.colorScheme) private var colorScheme

    private var trackColor: Color { FriendlyPalette.line(colorScheme) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(trackColor)
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(FriendlyPalette.accentHot)
                    .frame(width: max(0, geo.size.width * CGFloat(min(1, max(0, progress)))), height: 6)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Idle / Preparing / Uploading stage

private struct IdleStage: View {
    @Bindable var viewModel: ShareViewModel
    @Bindable var paywallCoordinator: PaywallCoordinator
    let onUpload: () async -> Void
    let onCancel: () -> Void
    var isPreparing: Bool = false
    var uploadProgress: Double? = nil
    var bytesSent: Int64 = 0
    var bytesTotal: Int64 = 0

    @State private var tier: Tier = .free
    @Environment(\.colorScheme) private var colorScheme

    // MARK: Theme helpers
    private var textColor: Color       { FriendlyPalette.text(colorScheme) }
    private var textDimColor: Color    { FriendlyPalette.textDim(colorScheme) }
    private var textFaintColor: Color  { FriendlyPalette.textFaint(colorScheme) }
    private var canvasColor: Color     { FriendlyPalette.canvas(colorScheme) }
    private var lineColor: Color       { FriendlyPalette.line(colorScheme) }
    private var lineStrongColor: Color { FriendlyPalette.lineStrong(colorScheme) }
    private var activeChipText: Color {
        colorScheme == .dark ? .white : FriendlyPalette.text(.light)
    }

    private var isUploading: Bool { uploadProgress != nil }
    private var effectiveProgress: Double { uploadProgress ?? 0 }
    private var progressPercent: Int { Int((effectiveProgress * 100).rounded()) }
    private var canSubmit: Bool { !viewModel.items.isEmpty && !isPreparing && !isUploading }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title + subtitle
            Text("Create a link")
                .font(.system(size: 24, weight: .bold))
                .tracking(-24 * 0.025)
                .foregroundStyle(textColor)

            Text("We'll upload and copy the link to your clipboard.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(textDimColor)
                .padding(.top, 4)

            // File card
            fileCard
                .padding(.top, 22)

            // Retention picker
            retentionSection
                .padding(.top, 18)

            // Notify toggle
            notifyRow
                .padding(.top, 12)

            // CTA
            ctaButton
                .padding(.top, 20)
        }
        .task {
            if let store = try? await SubscriptionStoreLocator.shared.current() {
                let snap = await store.currentSnapshot()
                tier = snap.isPro ? .pro(snap.tier ?? .monthly) : .free
                for await next in store.snapshotStream {
                    tier = next.isPro ? .pro(next.tier ?? .monthly) : .free
                }
            }
        }
    }

    // MARK: - File card

    private var fileCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let first = viewModel.items.first {
                    SheetFileIcon(contentType: first.contentType, size: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(first.filename)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(textColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(ByteCountFormatter.string(fromByteCount: first.sizeBytes, countStyle: .file)) · \(first.contentType)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(textDimColor)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                } else {
                    HStack(spacing: 10) {
                        ProgressView().tint(FriendlyPalette.accentHot)
                        Text("Preparing…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(textDimColor)
                    }
                    Spacer(minLength: 0)
                }
            }

            // Progress bar row — only when uploading/preparing
            if isPreparing || isUploading {
                HStack(spacing: 10) {
                    SheetProgressBar(progress: isPreparing ? 0.12 : effectiveProgress)
                        .frame(maxWidth: .infinity)

                    Text("\(isPreparing ? 0 : progressPercent)%")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(FriendlyPalette.accentHot)
                        .frame(minWidth: 36, alignment: .trailing)
                }
                .padding(.top, 14)
            }
        }
        .padding(16)
        .background(canvasColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(lineColor, lineWidth: 1)
        )
    }

    // MARK: - Retention section

    private var retentionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How long should the link work?")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(textColor)

            retentionChips
        }
    }

    private var retentionChips: some View {
        HStack(spacing: 8) {
            ForEach(RetentionPolicy.shareable, id: \.self) { policy in
                retentionChip(policy)
            }
        }
    }

    private func retentionChip(_ policy: RetentionPolicy) -> some View {
        let selected = viewModel.retentionPolicy == policy
        let isGated = policy.ttlSeconds > tier.caps.maxRetentionSeconds

        return Button {
            if isGated {
                paywallCoordinator.present(.longRetentionRequested(policy: policy))
            } else {
                viewModel.retentionPolicy = policy
            }
        } label: {
            HStack(spacing: 4) {
                Text(chipLabel(for: policy))
                    .font(.system(size: 13, weight: selected ? .bold : .semibold))
                    .foregroundStyle(selected ? activeChipText : textColor)
                if isGated {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(selected ? activeChipText.opacity(0.7) : textDimColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? FriendlyPalette.accentHot : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selected ? Color.clear : lineColor, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: policy, gated: isGated))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chipLabel(for policy: RetentionPolicy) -> String {
        switch policy {
        case .oneHour: return "1 hour"
        case .oneDay: return "24 hours"
        case .oneWeek: return "3 days"
        case .oneMonth: return "7 days"
        default: return policy.displayName
        }
    }

    private func accessibilityLabel(for policy: RetentionPolicy, gated: Bool) -> String {
        let base = policy.displayName
        return gated ? "\(base), Pro only" : base
    }

    // MARK: - Notify row

    private var notifyRow: some View {
        HStack(spacing: 12) {
            Text("🔕")
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 2) {
                Text("Notify me on open")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textColor)
                Text("Ping when someone views the link")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(textDimColor)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: notifyBinding)
                .labelsHidden()
                .tint(FriendlyPalette.accentHot)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(canvasColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(lineColor, lineWidth: 1)
        )
    }

    /// Bind to UserDefaults notification preference (best-effort; not a strict view-model field).
    private var notifyBinding: Binding<Bool> {
        Binding(
            get: {
                UserDefaults(suiteName: AppGroupPaths.groupIdentifier)?
                    .bool(forKey: "notify_on_open") ?? false
            },
            set: { newValue in
                UserDefaults(suiteName: AppGroupPaths.groupIdentifier)?
                    .set(newValue, forKey: "notify_on_open")
            }
        )
    }

    // MARK: - CTA button

    private var ctaButton: some View {
        let uploading = isPreparing || isUploading
        let labelText = uploading ? "Uploading…" : "Create link →"

        return Button {
            Task { await onUpload() }
        } label: {
            Text(labelText)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(FriendlyPalette.text(.light))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
                .background(FriendlyPalette.accentHot, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1 : 0.55)
        #if os(iOS)
        .keyboardShortcut(.defaultAction)
        #endif
    }
}

// MARK: - Success stage

private struct SuccessStage: View {
    let link: FastSharedCore.ShareLink
    let filename: String
    let deduped: Bool
    let retention: RetentionPolicy
    let onDone: () -> Void

    @State private var copied: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var textColor: Color    { FriendlyPalette.text(colorScheme) }
    private var textDimColor: Color { FriendlyPalette.textDim(colorScheme) }
    private var canvasColor: Color  { FriendlyPalette.canvas(colorScheme) }
    private var lineColor: Color    { FriendlyPalette.line(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // Hero — PlaneArc mark with success badge overlay
            SheetPlaneArc(size: 100, framed: false, ambient: true)
                .overlay(alignment: .bottomTrailing) {
                    ZStack {
                        Circle()
                            .fill(FriendlyPalette.successGreen)
                            .frame(width: 40, height: 40)
                        Text("✓")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 4, y: 4)
                }
                .padding(.top, 24)

            // Title
            Text("Link copied!")
                .font(.system(size: 30, weight: .bold))
                .tracking(-30 * 0.025)
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
                .padding(.top, 28)

            // Body
            Text("Paste it anywhere. It expires in \(retentionBodyText).")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(textDimColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, 8)

            // Link card
            linkCard
                .padding(.top, 20)

            // Expiry reminder
            expiryReminder
                .padding(.top, 12)

            // Buttons
            VStack(spacing: 10) {
                Button {
                    shareLink()
                } label: {
                    Text("Share the link ↗")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(FriendlyPalette.text(.light))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(FriendlyPalette.accentHot, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                #if os(iOS)
                .keyboardShortcut(.defaultAction)
                #endif

                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(textColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(canvasColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(lineColor, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .onAppear { copyIfNeeded() }
    }

    private var retentionBodyText: String {
        switch retention {
        case .oneHour: return "1 hour"
        case .oneDay: return "24 hours"
        case .oneWeek: return "7 days"
        case .oneMonth: return "30 days"
        default: return retention.displayName
        }
    }

    private var linkCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR LINK")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(textDimColor)

                HStack(spacing: 0) {
                    Text("fastsha.red/s/")
                        .foregroundStyle(textColor)
                    Text(link.token)
                        .foregroundStyle(FriendlyPalette.accentHot)
                }
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Text("✓")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(FriendlyPalette.successGreen)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(canvasColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(lineColor, lineWidth: 1)
        )
    }

    private var expiryReminder: some View {
        HStack(spacing: 10) {
            SheetRing(progress: 0.98, size: 24, stroke: 2.5)

            Text("\(retentionBodyText) ")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(FriendlyPalette.accentHot)
            + Text("before it expires")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(FriendlyPalette.accentHot)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FriendlyPalette.accentHot.opacity(0.09))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyIfNeeded() {
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            copied = false
        }
    }

    private func shareLink() {
        // Share extensions can't present UIActivityViewController — the link is
        // already on the pasteboard from the upload completion, so re-copy and
        // let the user paste wherever. The Done button dismisses the sheet.
        copyIfNeeded()
    }
}

// MARK: - Share-ext paywall sheet (lightweight)

/// Inline paywall surface for the share extension.
struct SharePaywallSheet: View {
    let trigger: PaywallTriggerContext
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(FriendlyPalette.accentHot)
            Text(headline)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(FriendlyPalette.text(colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text(subhead)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(FriendlyPalette.textDim(colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
            Button {
                if let url = URL(string: "fastsharedapp://paywall") {
                    openURL(url)
                }
                onDismiss()
            } label: {
                Text("OPEN FASTSHARED PRO")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(colorScheme == .dark ? FriendlyPalette.text(.light) : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(FriendlyPalette.accentHot, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)

            Button {
                onDismiss()
            } label: {
                Text("NOT NOW")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(FriendlyPalette.textDim(colorScheme))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .background(FriendlyPalette.ground(colorScheme).ignoresSafeArea())
    }

    private var headline: String {
        switch trigger {
        case .dailyCapReached: return "Free limit reached"
        case .cloudSyncRequested: return "Cross-device sync is Pro"
        case .longRetentionRequested: return "Extended retention is Pro"
        case .largeFileRequested: return "Larger files are Pro"
        case .serverForced: return "Upgrade to continue"
        }
    }

    private var subhead: String {
        switch trigger {
        case .dailyCapReached:
            return "Open FastShared to upgrade — your next link drops in instantly."
        case .cloudSyncRequested, .longRetentionRequested, .largeFileRequested, .serverForced:
            return "Open FastShared to see Pro plans and unlock."
        }
    }
}

// MARK: - Failure stage

private struct FailureStage: View {
    let reason: String
    let requestId: String
    let onRetry: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var textColor: Color      { FriendlyPalette.text(colorScheme) }
    private var textDimColor: Color   { FriendlyPalette.textDim(colorScheme) }
    private var textFaintColor: Color { FriendlyPalette.textFaint(colorScheme) }
    private var canvasColor: Color    { FriendlyPalette.canvas(colorScheme) }
    private var lineColor: Color      { FriendlyPalette.line(colorScheme) }

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(FriendlyPalette.UrgencyTier.critical.text)

            VStack(spacing: 6) {
                Text("Upload failed")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(textColor)
                Text(reason)
                    .font(.system(size: 14, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(textDimColor)
                    .padding(.horizontal, 12)
            }

            Text("id \(requestId)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(textFaintColor)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(textDimColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(canvasColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(lineColor, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)

                Button(action: onRetry) {
                    Text("Try again")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(FriendlyPalette.text(.light))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(FriendlyPalette.accentHot, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                #if os(iOS)
                .keyboardShortcut(.defaultAction)
                #endif
            }
        }
        .frame(maxWidth: .infinity)
    }
}
