import SwiftUI
import FastSharedCore

#if canImport(UIKit)
import UIKit
#endif

struct ShareRootView: View {
    @Bindable var viewModel: ShareViewModel
    let onUpload: () async -> Void
    let onCancel: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            BrandPalette.canvas.ignoresSafeArea()
            content
                .padding(24)
                .frame(minWidth: 360, minHeight: 420)
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(BrandPalette.milk)
        .animation(BrandMotion.transition, value: phaseKey)
    }

    // WHY: a discriminant key lets SwiftUI animate view identity across phases without comparing associated values.
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
            IdleStage(viewModel: viewModel, onUpload: onUpload, onCancel: onCancel)
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

// MARK: - Stages

private struct IdleStage: View {
    @Bindable var viewModel: ShareViewModel
    let onUpload: () async -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if viewModel.items.isEmpty {
                preparingList
            } else {
                itemsList
            }
            retentionSection
            Spacer(minLength: 4)
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                (Text("fastshared")
                    .foregroundColor(BrandPalette.milk)
                 + Text(".")
                    .foregroundColor(BrandPalette.amber))
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.2)
                Text("Stage a temporary link")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.4)
            }
            Spacer()
            Image(systemName: "paperplane.fill")
                .font(.title2)
                .foregroundStyle(BrandPalette.amber)
        }
    }

    private var preparingList: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(BrandPalette.amber)
            Text("Preparing files")
                .font(.footnote)
                .foregroundStyle(BrandPalette.milk.opacity(0.6))
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var itemsList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(viewModel.items) { item in
                    StagedRow(item: item)
                }
            }
        }
        .frame(maxHeight: 180)
    }

    private var retentionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Link valid for")
                    .font(.caption.weight(.medium))
            } icon: {
                Image(systemName: "timer")
            }
            .foregroundStyle(BrandPalette.dust)

            Picker("Link valid for", selection: $viewModel.retentionPolicy) {
                ForEach(RetentionPolicy.shareable, id: \.self) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(BrandPalette.amber)

            Text("Link expires in \(viewModel.retentionPolicy.displayName). Media is deleted 24 hours later.")
                .font(.caption2)
                .foregroundStyle(BrandPalette.milk.opacity(0.55))
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel", role: .cancel, action: onCancel)
                .buttonStyle(.plain)
                .foregroundStyle(BrandPalette.milk.opacity(0.7))
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button {
                Task { await onUpload() }
            } label: {
                Text("Upload")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BrandPalette.ink)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(BrandPalette.amber, in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.items.isEmpty)
            .opacity(viewModel.items.isEmpty ? 0.4 : 1)
        }
    }
}

private struct StagedRow: View {
    let item: StagedItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: item.contentType))
                .font(.title3)
                .frame(width: 34, height: 34)
                .foregroundStyle(BrandPalette.ember)
                .background(BrandPalette.violet.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(BrandPalette.milk)
                Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(BrandPalette.milk.opacity(0.55))
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(BrandPalette.nightshade.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func iconName(for contentType: String) -> String {
        if contentType.hasPrefix("image/") { return "photo" }
        if contentType.hasPrefix("video/") { return "film" }
        if contentType.hasPrefix("audio/") { return "waveform" }
        if contentType == "application/pdf" { return "doc.richtext" }
        return "doc"
    }
}

private struct PreparingStage: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            OriginSphere(progress: 0, pulsing: true, determinate: false)
                .frame(width: 120, height: 120)
            VStack(spacing: 4) {
                Text("Preparing")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.3)
                Text("Hashing your file")
                    .font(.footnote)
                    .foregroundStyle(BrandPalette.milk.opacity(0.6))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct UploadingStage: View {
    let progress: Double
    let bytesSent: Int64
    let bytesTotal: Int64
    let retention: RetentionPolicy

    private var percent: Int { Int((progress * 100).rounded()) }
    private var sentString: String { ByteCountFormatter.string(fromByteCount: bytesSent, countStyle: .file) }
    private var totalString: String { ByteCountFormatter.string(fromByteCount: bytesTotal, countStyle: .file) }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            OriginSphere(progress: progress, pulsing: true, determinate: true)
                .frame(width: 128, height: 128)
            VStack(spacing: 6) {
                Text("Uploading")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.3)
                Text("\(sentString) of \(totalString)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(BrandPalette.milk.opacity(0.65))
                Text("\(percent)%")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(-1)
                    .foregroundStyle(BrandPalette.amber)
                    .contentTransition(.numericText())
            }
            // WHY: linear bar lives alongside the sphere so progress is readable without relying on color alone.
            ProgressView(value: max(0, min(1, progress)))
                .progressViewStyle(.linear)
                .tint(BrandPalette.amber)
                .frame(maxWidth: 260)
            expiryFootnote
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var expiryFootnote: some View {
        HStack(spacing: 6) {
            Image(systemName: "hourglass.bottomhalf.fill")
                .foregroundStyle(BrandPalette.coral)
            Text("Link expires in \(retention.displayName) once ready")
                .font(.caption)
                .foregroundStyle(BrandPalette.milk.opacity(0.6))
        }
    }
}

private struct SuccessStage: View {
    let link: FastSharedCore.ShareLink
    let filename: String
    let deduped: Bool
    let onDone: () -> Void

    @State private var copied: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            header
            urlPill
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                ExpiryCountdown(expiresAt: link.expiresAt, now: ctx.date)
            }
            Spacer(minLength: 8)
            Button(action: onDone) {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BrandPalette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(BrandPalette.amber, in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(BrandPalette.amber.opacity(0.18))
                    .frame(width: 96, height: 96)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(BrandPalette.amber)
            }
            if deduped {
                Label("Already uploaded", systemImage: "sparkles")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BrandPalette.ember)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(BrandPalette.violet.opacity(0.6), in: Capsule())
            }
            Text(filename)
                .font(.footnote)
                .foregroundStyle(BrandPalette.milk.opacity(0.6))
                .lineLimit(1)
        }
    }

    private var urlPill: some View {
        Button(action: copy) {
            HStack(spacing: 8) {
                Image(systemName: copied ? "checkmark" : "link")
                    .font(.system(size: 14, weight: .semibold))
                Text(copied ? "Copied" : link.shortURL.absoluteString)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(BrandPalette.milk)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 320)
            .background(
                Capsule()
                    .fill(BrandPalette.nightshade)
                    .overlay(
                        Capsule()
                            .strokeBorder(BrandPalette.arc, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied link" : "Tap to copy \(link.shortURL.absoluteString)")
    }

    private func copy() {
        Clipboard.make().copy(link.shortURL.absoluteString)
        copied = true
        // WHY: one-tap copy is the hero moment — revert the affordance after a beat so the URL is still reachable.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            copied = false
        }
    }
}

private struct ExpiryCountdown: View {
    let expiresAt: Date
    let now: Date

    var body: some View {
        let remaining = max(0, expiresAt.timeIntervalSince(now))
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .foregroundStyle(BrandPalette.coral)
            Text("Link expires in")
                .font(.footnote)
                .foregroundStyle(BrandPalette.milk.opacity(0.65))
            Text(Self.format(remaining))
                .font(.footnote.monospaced().weight(.medium))
                .foregroundStyle(BrandPalette.dust)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let days = s / 86_400
        let hours = (s % 86_400) / 3_600
        let minutes = (s % 3_600) / 60
        let secs = s % 60
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

private struct FailureStage: View {
    let reason: String
    let requestId: String
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(BrandPalette.coral)
            VStack(spacing: 6) {
                Text("Upload failed")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.3)
                Text(reason)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BrandPalette.milk.opacity(0.75))
                    .padding(.horizontal, 12)
            }
            Text("id \(requestId)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(BrandPalette.milk.opacity(0.4))
            Spacer(minLength: 8)
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.body.weight(.medium))
                        .foregroundStyle(BrandPalette.milk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(BrandPalette.nightshade, in: Capsule())
                }
                .buttonStyle(.plain)
                Button(action: onRetry) {
                    Text("Retry")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BrandPalette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(BrandPalette.amber, in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Origin sphere

/// The brand's warm origin sphere, re-used as the upload indicator. Pulses when active.
private struct OriginSphere: View {
    let progress: Double
    let pulsing: Bool
    let determinate: Bool

    @State private var pulse: Bool = false

    private var reduceMotion: Bool {
        #if canImport(UIKit)
        return UIAccessibility.isReduceMotionEnabled
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack {
            // Outer soft halo — the brand's concentric glow.
            Circle()
                .fill(BrandPalette.amber.opacity(pulsing && !reduceMotion ? (pulse ? 0.28 : 0.12) : 0.18))
                .scaleEffect(pulsing && !reduceMotion ? (pulse ? 1.0 : 0.86) : 0.9)
                .blur(radius: 14)
            // Ring — determinate when we have real progress, otherwise indeterminate spin.
            if determinate {
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, progress)))
                    .stroke(BrandPalette.arc,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(BrandPalette.arc,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(reduceMotion ? 0 : (pulse ? 360 : 0)))
            }
            // Core — the sphere itself.
            Circle()
                .fill(RadialGradient(colors: [BrandPalette.ember, BrandPalette.amber],
                                     center: .center,
                                     startRadius: 0,
                                     endRadius: 60))
                .padding(22)
                .shadow(color: BrandPalette.amber.opacity(0.55), radius: 18)
        }
        .onAppear {
            guard pulsing, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: determinate ? 1.6 : 1.2).repeatForever(autoreverses: determinate)) {
                pulse = true
            }
        }
        .accessibilityLabel(determinate ? "Uploading \(Int(progress * 100)) percent" : "Preparing")
    }
}
