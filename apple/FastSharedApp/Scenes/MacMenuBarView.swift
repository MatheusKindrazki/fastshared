#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import FastSharedCore
import UniformTypeIdentifiers

/// macOS menu bar popover — 360pt wide, auto height.
///
/// Shows the brand lockup header, a drag-and-drop upload zone, and a "recent"
/// list of the last 3 shares with urgency dots and countdown labels.
///
/// Wired up as a `MenuBarExtra(.window)` in `FastSharedApp.swift`.
struct MacMenuBarView: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(\.uploadService) private var uploadService
    @Environment(\.clipboard) private var clipboard
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: [SortDescriptor(\ShareLinkEntity.createdAt, order: .reverse)])
    private var allShares: [ShareLinkEntity]

    @State private var isDragTargeted: Bool = false
    @State private var isUploading: Bool = false

    // MARK: - Adaptive palette — HIG semantic (NSColor bridges).

    private var groundColor: Color { Color(nsColor: .windowBackgroundColor) }
    private var canvasColor: Color { Color(nsColor: .controlBackgroundColor) }
    private var surface0Color: Color { Color(nsColor: .underPageBackgroundColor) }
    private var textColor: Color { Color(nsColor: .labelColor) }
    private var textDimColor: Color { Color(nsColor: .secondaryLabelColor) }
    private var textFaintColor: Color { Color(nsColor: .tertiaryLabelColor) }
    private var lineColor: Color { Color(nsColor: .separatorColor) }

    // MARK: - Derived data

    private var now: Date { Date() }

    private var recentShares: [ShareLinkEntity] {
        allShares
            .filter { $0.linkStatus == LinkStatus.active.rawValue && $0.expiresAt > now }
            .prefix(3)
            .map { $0 }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            lineColor.frame(height: 1)
            dropZoneCard
                .padding(12)
            recentBlock
        }
        .frame(width: 360)
        .background(groundColor)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            BrandLockup(markSize: 22, textSize: 15)

            Spacer()

            Text("⌘⇧S")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(textDimColor)
                .tracking(0.05 * 11)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(surface0Color)
                )
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }

    // MARK: - Drop zone card

    private var dropZoneCard: some View {
        VStack(spacing: 4) {
            Text("📎")
                .font(.system(size: 22))
                .padding(.bottom, 4)

            Text(isUploading ? "Uploading…" : "Drop a file to share")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(textColor)

            Text("Link copied automatically")
                .font(.system(size: 11))
                .foregroundStyle(textDimColor)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BrandPalette.accentHot.opacity(isDragTargeted ? 0.14 : 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            BrandPalette.accentHot.opacity(isDragTargeted ? 0.50 : 0.25),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5])
                        )
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
        .onDrop(of: [UTType.fileURL, UTType.item], isTargeted: $isDragTargeted) { providers in
            handleDropProviders(providers)
            return true
        }
    }

    // MARK: - Recent block

    @ViewBuilder
    private var recentBlock: some View {
        if !recentShares.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("RECENT")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(textDimColor)
                    .tracking(0.08 * 11)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                    .padding(.horizontal, 6)

                ForEach(recentShares, id: \.token) { share in
                    MenuBarShareRow(
                        share: share,
                        now: now,
                        textColor: textColor,
                        textDimColor: textDimColor,
                        lineColor: lineColor,
                        onCopy: {
                            clipboard.copy(share.shortURLString)
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Drop handler

    private func handleDropProviders(_ providers: [NSItemProvider]) {
        guard let service = uploadService else { return }
        isUploading = true
        Task {
            defer { isUploading = false }
            var urls: [URL] = []
            for provider in providers {
                if let url = await loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else { return }
            _ = try? await service.enqueueDrop(urls: urls)
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}

// MARK: - MenuBarShareRow

private struct MenuBarShareRow: View {
    let share: ShareLinkEntity
    let now: Date
    let textColor: Color
    let textDimColor: Color
    let lineColor: Color
    let onCopy: () -> Void

    private var remaining: TimeInterval { max(0, share.expiresAt.timeIntervalSince(now)) }
    private var tier: ExpiryTier { ExpiryTier.tier(for: remaining) }

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 10) {
                // Urgency dot
                Circle()
                    .fill(tier.urgencyColor)
                    .frame(width: 8, height: 8)

                // Filename
                Text(share.originalFilename ?? share.token)
                    .font(.system(size: 13))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Remaining time
                Text(ExpiryFormatter.remaining(remaining))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tier.urgencyColor)
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy link")
    }
}

#Preview("MacMenuBarView") {
    MacMenuBarView()
        .preferredColorScheme(.dark)
}
#endif
