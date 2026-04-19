import SwiftUI
import FastSharedCore

#if canImport(UIKit)
import UIKit
#endif

/// Share extension root — `design/screens.jsx` → `ShareSheet()` + `ShareSuccess()`.
///
/// Five phases backed by `ShareViewModel`. The sheet itself sits on top of a
/// faded host-app backdrop; the upload state is mirrored into the Dynamic
/// Island via LiveActivity elsewhere.
struct ShareRootView: View {
    @Bindable var viewModel: ShareViewModel
    /// Process-scoped coordinator owned by ShareViewController; shared here
    /// so a gated-retention tap triggers the paywall sheet below.
    @Bindable var paywallCoordinator: PaywallCoordinator
    let onUpload: () async -> Void
    let onCancel: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dim the host context so the sheet reads as modal.
            LinearGradient(
                colors: [BrandPalette.ground.opacity(0.6),
                         BrandPalette.ground.opacity(0.85),
                         BrandPalette.ground],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            content
                .padding(24)
                .background(BrandPalette.surface0, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(BrandPalette.lineStrong, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 32, y: -12)
                .padding(12)
                .frame(minWidth: 360, minHeight: 420)
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(BrandPalette.text)
        .animation(BrandMotion.transition, value: phaseKey)
        .sheet(item: $paywallCoordinator.pending) { trigger in
            // WHY: the share ext sheet host is this root; PaywallView lives in
            // the main-app target so we project a lightweight inline paywall
            // surface here. The upgrade flow itself (actual StoreKit call) is
            // delegated through `SubscriptionStoreLocator`.
            SharePaywallSheet(trigger: trigger) {
                paywallCoordinator.dismiss()
            }
        }
    }

    // WHY: a discriminant key lets SwiftUI animate view identity across phases.
    private var phaseKey: Int {
        switch viewModel.phase {
        case .idle: return 0
        case .preparing: return 1
        case .uploading: return 2
        case .success: return 3
        case .failed: return 4
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            IdleStage(viewModel: viewModel,
                      paywallCoordinator: paywallCoordinator,
                      onUpload: onUpload,
                      onCancel: onCancel)
        case .preparing:
            PreparingStage()
        case .uploading(let progress, let sent, let total):
            UploadingStage(progress: progress,
                           bytesSent: sent,
                           bytesTotal: total,
                           retention: viewModel.retentionPolicy)
        case .success(let link, let filename, let deduped):
            SuccessStage(link: link,
                         filename: filename,
                         deduped: deduped,
                         onDone: onDismiss)
        case .failed(let reason, let requestId):
            FailureStage(reason: reason,
                         requestId: requestId,
                         onRetry: { Task { await onUpload() } },
                         onCancel: onCancel)
        }
    }
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
            Circle().stroke(BrandPalette.line, lineWidth: stroke)
                .frame(width: size, height: size)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(BrandPalette.amberAccent.hot, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}

/// Inline mono label for the share extension.
private struct SheetMono: View {
    let text: String
    var size: CGFloat = 11
    var track: CGFloat = 1.6
    var color: Color = BrandPalette.textDim
    var weight: Font.Weight = .semibold

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: weight, design: .monospaced))
            .tracking(track)
            .foregroundStyle(color)
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

    var body: some View {
        let accent = BrandPalette.amberAccent
        let corner = size * (32.0 / 140.0)
        let arcStrokeWidth = size * (9.0 / 140.0)

        ZStack {
            if ambient {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent.hot.opacity(0.21), .clear],
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
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(BrandPalette.surface0)
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .stroke(BrandPalette.lineStrong, lineWidth: 1)
                    )
                    .frame(width: size, height: size)
            }

            SheetArcPath()
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: accent.fade.opacity(0), location: 0),
                            .init(color: accent.hot.opacity(0.95), location: 0.5),
                            .init(color: accent.soft, location: 1),
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
///
/// Mirrors `apple/FastSharedApp/Components/BrandLockup.swift` — the canonical
/// mark+wordmark pair (amber period as the only accent). Kept in sync by hand.
private struct SheetBrandLockup: View {
    var markSize: CGFloat = 20
    var textSize: CGFloat = 13

    var body: some View {
        let accent = BrandPalette.amberAccent
        HStack(spacing: 8) {
            SheetPlaneArc(size: markSize)
                .accessibilityHidden(true)
            (
                Text("fastshared")
                    .foregroundStyle(BrandPalette.text)
                + Text(".")
                    .foregroundStyle(accent.hot)
            )
            .font(.system(size: textSize, weight: .bold))
            .tracking(-textSize * 0.02)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("fastshared")
    }
}

/// Inline file glyph for the share extension.
private struct SheetGlyph: View {
    let contentType: String
    var size: CGFloat = 34

    var body: some View {
        let accent = BrandPalette.amberAccent
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(accent.hot.opacity(0.10))
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(accent.hot.opacity(0.20), lineWidth: 1)
            )
            .overlay(
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.50, weight: .regular))
                    .foregroundStyle(accent.hot)
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

// MARK: - Idle stage (pick retention, confirm upload)

private struct IdleStage: View {
    @Bindable var viewModel: ShareViewModel
    @Bindable var paywallCoordinator: PaywallCoordinator
    let onUpload: () async -> Void
    let onCancel: () -> Void

    @State private var tier: Tier = .free

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if viewModel.items.isEmpty {
                preparingPlaceholder
            } else {
                stagedCard
            }

            retentionPicker

            Spacer(minLength: 6)

            ctaRow
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

    private var header: some View {
        HStack(alignment: .top) {
            // v3 share-ext header — BrandLockup at 20/13 per screens.jsx `ShareSheet()`.
            SheetBrandLockup(markSize: 20, textSize: 13)
            Spacer()
            Button(action: onCancel) {
                Text("CANCEL")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(BrandPalette.textDim)
            }
            .buttonStyle(.plain)
        }
    }

    private var preparingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Stage a temporary link")
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(BrandPalette.text)
            HStack(spacing: 10) {
                ProgressView().tint(BrandPalette.amberAccent.hot)
                SheetMono(text: "Preparing files")
            }
        }
    }

    private var stagedCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stage a temporary link")
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(BrandPalette.text)

            if let first = viewModel.items.first {
                HStack(spacing: 12) {
                    SheetGlyph(contentType: first.contentType)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(first.filename)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BrandPalette.text)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text("\(ByteCountFormatter.string(fromByteCount: first.sizeBytes, countStyle: .file)) · \(first.contentType)")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(BrandPalette.textFaint)
                    }

                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BrandPalette.paper)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(BrandPalette.line, lineWidth: 1)
                        )
                )

                if viewModel.items.count > 1 {
                    Text("+\(viewModel.items.count - 1) more will upload in the background.")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(BrandPalette.textFaint)
                }
            }
        }
    }

    private var retentionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetMono(text: "link valid for", color: BrandPalette.textFaint)

            GatedRetentionPicker(
                selection: $viewModel.retentionPolicy,
                tier: tier,
                onPaywall: { trigger in
                    paywallCoordinator.present(trigger)
                }
            )

            Text(retentionFootnote)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(BrandPalette.textFaint)
        }
    }

    private var retentionFootnote: String {
        "Link expires in \(viewModel.retentionPolicy.displayName). Media deleted 24h later."
    }

    private var ctaRow: some View {
        let accent = BrandPalette.amberAccent
        return Button {
            Task { await onUpload() }
        } label: {
            HStack(spacing: 10) {
                Text("UPLOAD")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(1.8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Color(red: 0.07, green: 0.02, blue: 0.04))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(accent.hot, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.items.isEmpty)
        .opacity(viewModel.items.isEmpty ? 0.45 : 1)
        #if os(iOS)
        .keyboardShortcut(.defaultAction)
        #endif
    }
}

// MARK: - Preparing stage

private struct PreparingStage: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            SheetRing(progress: 0.12, size: 96, stroke: 5)
                .rotationEffect(.degrees(0))
            VStack(spacing: 6) {
                Text("Preparing")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(BrandPalette.text)
                SheetMono(text: "hashing your file", color: BrandPalette.textFaint)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Uploading stage

private struct UploadingStage: View {
    let progress: Double
    let bytesSent: Int64
    let bytesTotal: Int64
    let retention: RetentionPolicy

    private var percent: Int { Int((progress * 100).rounded()) }
    private var sentString: String { ByteCountFormatter.string(fromByteCount: bytesSent, countStyle: .file) }
    private var totalString: String { ByteCountFormatter.string(fromByteCount: bytesTotal, countStyle: .file) }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            SheetRing(progress: progress, size: 128, stroke: 7)
                .overlay(
                    VStack(spacing: 2) {
                        Text("\(percent)%")
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .tracking(-0.6)
                            .foregroundStyle(BrandPalette.text)
                            .contentTransition(.numericText())
                        SheetMono(text: "uploading", size: 9, track: 1.2, color: BrandPalette.textFaint)
                    }
                )

            Text("\(sentString) / \(totalString)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(BrandPalette.textDim)

            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 10, weight: .semibold))
                Text("link valid for \(retention.displayName) once ready")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
            }
            .foregroundStyle(BrandPalette.textFaint)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Success stage

private struct SuccessStage: View {
    let link: FastSharedCore.ShareLink
    let filename: String
    let deduped: Bool
    let onDone: () -> Void

    @State private var copied: Bool = false

    var body: some View {
        let accent = BrandPalette.amberAccent
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            // v3 success hero — PlaneArc framed + ambient, per screens.jsx
            // `ShareSuccess()` (`<PlaneArc size={160} framed ambient/>`).
            SheetPlaneArc(size: 160, framed: true, ambient: true)

            SheetMono(text: "link copied · handoff ready", color: accent.hot)

            Text("Done.")
                .font(.system(size: 36, weight: .bold))
                .tracking(-1.5)
                .foregroundStyle(BrandPalette.text)
            Text("Link is on your clipboard and waiting on your Mac.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(BrandPalette.textDim)
                .multilineTextAlignment(.center)

            urlTicket

            Button(action: onDone) {
                Text("DONE")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(Color(red: 0.07, green: 0.02, blue: 0.04))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(accent.hot, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            #if os(iOS)
            .keyboardShortcut(.defaultAction)
            #endif

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .onAppear { copyIfNeeded() }
    }

    private var urlTicket: some View {
        let accent = BrandPalette.amberAccent
        return HStack(spacing: 12) {
            Image(systemName: copied ? "checkmark.circle.fill" : "link")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent.hot)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text("fastsha.red/s/")
                        .foregroundStyle(BrandPalette.text)
                    Text(link.token)
                        .foregroundStyle(accent.hot)
                }
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

                Text("expires \(link.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(BrandPalette.textFaint)
            }

            Spacer(minLength: 0)

            Button(action: copy) {
                Text(copied ? "COPIED" : "COPY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color(red: 0.07, green: 0.02, blue: 0.04))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(accent.hot, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BrandPalette.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(BrandPalette.lineStrong, lineWidth: 1)
                )
        )
    }

    private func copyIfNeeded() {
        // WHY: The upload orchestrator already copies to the clipboard on
        // completion. We mirror the visual state so the "COPY" pill reflects it.
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            copied = false
        }
    }

    private func copy() {
        Clipboard.make().copy(link.shortURL.absoluteString)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            copied = false
        }
    }
}

// MARK: - Share-ext paywall sheet (lightweight)

/// Inline paywall surface for the share extension.
///
/// The main app's `PaywallView` lives in the FastSharedApp target and can't be
/// reached from here; we present a stripped-down summary that nudges the user
/// back to the main app to complete the purchase. A future iteration can host
/// the full paywall here by moving PaywallView into FastSharedCore.
struct SharePaywallSheet: View {
    let trigger: PaywallTriggerContext
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        let accent = BrandPalette.amberAccent
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(accent.hot)
            // TODO(i18n)
            Text(headline)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(BrandPalette.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text(subhead)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(BrandPalette.textDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
            Button {
                if let url = URL(string: "fastsharedapp://paywall") {
                    openURL(url)
                }
                onDismiss()
            } label: {
                // TODO(i18n)
                Text("OPEN FASTSHARED PRO")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color(red: 0.07, green: 0.02, blue: 0.04))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(accent.hot, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)

            Button {
                onDismiss()
            } label: {
                // TODO(i18n)
                Text("NOT NOW")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(BrandPalette.textDim)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .background(BrandPalette.ground.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var headline: String {
        // TODO(i18n)
        switch trigger {
        case .dailyCapReached: return "Free limit reached"
        case .cloudSyncRequested: return "Cross-device sync is Pro"
        case .longRetentionRequested: return "Extended retention is Pro"
        case .largeFileRequested: return "Larger files are Pro"
        case .serverForced: return "Upgrade to continue"
        }
    }

    private var subhead: String {
        // TODO(i18n)
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

    var body: some View {
        let accent = BrandPalette.amberAccent
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(accent.fade)

            VStack(spacing: 6) {
                Text("Upload failed")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(BrandPalette.text)
                Text(reason)
                    .font(.system(size: 14, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BrandPalette.textDim)
                    .padding(.horizontal, 12)
            }

            SheetMono(text: "id \(requestId)", size: 10, color: BrandPalette.textFaint)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("CANCEL")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(BrandPalette.textDim)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(BrandPalette.paper)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(BrandPalette.line, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)

                Button(action: onRetry) {
                    Text("RETRY")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Color(red: 0.07, green: 0.02, blue: 0.04))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(accent.hot, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
